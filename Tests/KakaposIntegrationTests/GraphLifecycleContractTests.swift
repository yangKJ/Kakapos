//
//  GraphLifecycleContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/11/6.
//

import CoreMedia
import XCTest
@testable import KakaposMediaCore

final class GraphLifecycleContractTests: XCTestCase {
    func testFanOutWaitsForEveryConsumerAndPreservesFirstError() {
        let output = MediaOutputNode()
        let first = output.add(consumer: DeferredGraphConsumer())
        let second = output.add(consumer: DeferredGraphConsumer())
        var results: [Result<Void, Error>] = []
        output.transmit(GraphFrame()) { results.append($0) }

        second.complete(.failure(NSError(domain: "首次失败", code: 2)))
        second.complete(.failure(NSError(domain: "重复失败", code: 3)))
        XCTAssertTrue(results.isEmpty)
        first.complete(.failure(NSError(domain: "后续失败", code: 1)))
        XCTAssertEqual(results.count, 1)
        guard case .failure(let error) = results.first else { return XCTFail("必须返回首次错误") }
        XCTAssertEqual((error as NSError).domain, "首次失败")
    }

    func testFanOutCancellationSkipsRemainingConsumersButDrainsAcceptedWork() {
        let output = MediaOutputNode()
        let accepted = output.add(consumer: DeferredGraphConsumer())
        let skipped = output.add(consumer: DeferredGraphConsumer())
        var shouldContinue = true
        accepted.onConsume = { shouldContinue = false }
        var completions = 0
        output.transmit(GraphFrame(), shouldContinue: { shouldContinue }) { _ in completions += 1 }

        XCTAssertEqual(accepted.consumed, 1)
        XCTAssertEqual(skipped.consumed, 0)
        XCTAssertEqual(completions, 0)
        accepted.complete(.success(()))
        XCTAssertEqual(completions, 1)
    }

    func testConcurrentFanOutCompletesOnceOnLastConsumerQueue() {
        let output = MediaOutputNode()
        let consumers = (0..<24).map { _ in output.add(consumer: DeferredGraphConsumer()) }
        let queue = DispatchQueue(label: "com.condy.kakapos.test.fan-out", attributes: .concurrent)
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let completed = expectation(description: "全部消费者完成")
        completed.assertForOverFulfill = true
        output.transmit(GraphFrame()) { result in
            XCTAssertNotNil(try? result.get())
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), true)
            completed.fulfill()
        }
        DispatchQueue.concurrentPerform(iterations: consumers.count) { index in
            queue.sync {
                consumers[index].complete(.success(()))
                consumers[index].complete(.success(()))
            }
        }
        wait(for: [completed], timeout: 1)
    }

    func testNestedGraphFinishWaitsForAllSinksAndIgnoresDuplicateCallbacks() {
        let rootSink = DeferredGraphSink()
        let childSink = DeferredGraphSink()
        let root = MediaGraphBranch(sinks: [rootSink], children: [MediaGraphBranch(sinks: [childSink])])
        let graph = MediaGraph(source: GraphSource(), branches: [root])
        var completions = 0
        graph.completionHandler = { completions += 1 }
        graph.start()
        graph.stop()
        rootSink.completeFinish(.success(()))
        rootSink.completeFinish(.success(()))
        XCTAssertEqual(completions, 0)
        childSink.completeFinish(.success(()))
        childSink.completeFinish(.success(()))
        XCTAssertEqual(completions, 1)
    }

    func testNestedGraphFinishPreservesFirstFailureAfterDraining() {
        let rootSink = DeferredGraphSink()
        let childSink = DeferredGraphSink()
        let root = MediaGraphBranch(sinks: [rootSink], children: [MediaGraphBranch(sinks: [childSink])])
        let graph = MediaGraph(source: GraphSource(), branches: [root])
        var errors: [NSError] = []
        graph.errorHandler = { errors.append($0 as NSError) }
        graph.completionHandler = { XCTFail("失败不能发布成功") }
        graph.start()
        graph.stop()
        childSink.completeFinish(.failure(NSError(domain: "首次失败", code: 2)))
        XCTAssertTrue(errors.isEmpty)
        rootSink.completeFinish(.failure(NSError(domain: "后续失败", code: 1)))
        XCTAssertEqual(errors.map(\.domain), ["首次失败"])
    }

    func testReconnectPreservesAcceptedProcessorWork() {
        let source = GraphSource()
        let processor = DeferredGraphProcessor()
        let started = expectation(description: "处理已开始")
        processor.onStart = { started.fulfill() }
        let sink = DeferredGraphSink()
        let graph = MediaGraph(source: source, branches: [MediaGraphBranch(processors: [processor], sinks: [sink])])
        let finished = expectation(description: "重连后在途帧完成")
        graph.completionHandler = { finished.fulfill() }
        graph.start()
        source.delegate?.mediaSource(source, didOutput: GraphFrame())
        wait(for: [started], timeout: 1)
        graph.append(MediaGraphBranch())
        graph.stop()
        let sinkFinishing = expectation(description: "sink 收尾已开始")
        sink.onFinish = { sinkFinishing.fulfill() }
        processor.complete()
        wait(for: [sinkFinishing], timeout: 1)
        sink.completeFinish(.success(()))
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(sink.consumed, 1)
    }

    func testReleasedGraphDoesNotRetainItsBranchTree() {
        weak var releasedRoot: MediaGraphBranch?
        weak var releasedChild: MediaGraphBranch?
        do {
            let child = MediaGraphBranch(sinks: [DeferredGraphSink()])
            let root = MediaGraphBranch(children: [child])
            releasedRoot = root
            releasedChild = child
            let graph = MediaGraph(source: GraphSource(), branches: [root])
            graph.cancel()
        }
        XCTAssertNil(releasedRoot)
        XCTAssertNil(releasedChild)
    }

    func testNestedGraphConstructionPerformance() {
        measure {
            var branch = MediaGraphBranch(sinks: [DeferredGraphSink()])
            for _ in 0..<10 { branch = MediaGraphBranch(children: [branch]) }
            let graph = MediaGraph(source: GraphSource(), branches: [branch])
            graph.cancel()
        }
    }
}

private struct GraphFrame: MediaFrame {
    var metadata = FrameMetadata(presentationTime: .zero)
}

private final class GraphSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    func start() {}
    func pause() {}
    func resume() {}
    func stop() { delegate?.mediaSourceDidFinish(self) }
    func cancel() {}
}

private final class DeferredGraphConsumer: MediaFrameConsumerNode, @unchecked Sendable {
    var onConsume: (() -> Void)?
    private var completion: ((Result<Void, Error>) -> Void)?
    private(set) var consumed = 0

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        consumed += 1
        onConsume?()
    }

    func complete(_ result: Result<Void, Error>) { completion?(result) }
}

private final class DeferredGraphSink: MediaSink {
    var onFinish: (() -> Void)?
    private var finishCompletion: ((Result<Void, Error>) -> Void)?
    private(set) var consumed = 0

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        consumed += 1
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        finishCompletion = completion
        onFinish?()
    }

    func completeFinish(_ result: Result<Void, Error>) { finishCompletion?(result) }
}

private final class DeferredGraphProcessor: FrameProcessor {
    var onStart: (() -> Void)?
    private var completion: ((Result<MediaFrame, Error>) -> Void)?

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        self.completion = completion
        onStart?()
    }

    func complete() { completion?(.success(GraphFrame())) }
}
