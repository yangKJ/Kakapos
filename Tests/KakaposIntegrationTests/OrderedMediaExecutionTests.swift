// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
import KakaposVideo
@testable import KakaposMediaCore
@testable import KakaposCamera

final class OrderedMediaExecutionTests: XCTestCase {
    func testParallelCompletionIsDeliveredInAdmissionOrder() throws {
        let processor = Round2DeferredProcessor()
        let output = Round2LockedValues()
        let done = expectation(description: "三帧按接纳顺序确认"); done.expectedFulfillmentCount = 3
        let chain = MediaProcessorChain(processors: [processor], sinks: [PixelBufferSink { output.append(Int($0.metadata.frameIndex!)) }])
        for i in 0..<3 { chain.consume(try Round2Fixtures.frame(i)) { _ in done.fulfill() } }
        try waitForPending(processor, count: 3)
        processor.complete(2); processor.complete(1)
        XCTAssertEqual(output.values, [])
        processor.complete(0)
        wait(for: [done], timeout: 3)
        XCTAssertEqual(output.values, [0, 1, 2])
    }

    func testAllFourFrameCompletionPermutationsPreserveDeliveryOrder() throws {
        func permutations(_ values: [Int]) -> [[Int]] {
            if values.isEmpty { return [[]] }
            return values.flatMap { first in permutations(values.filter { $0 != first }).map { [first] + $0 } }
        }
        let frame = try Round2Fixtures.frame(0)
        for order in permutations([0, 1, 2, 3]) {
            let processor = Round2DeferredProcessor()
            let values = Round2LockedValues()
            let done = expectation(description: "排列保序"); done.expectedFulfillmentCount = 4
            let chain = MediaProcessorChain(processors: [processor], sinks: [PixelBufferSink { values.append(Int($0.metadata.frameIndex!)) }])
            for i in 0..<4 {
                var input = frame; input.metadata.frameIndex = Int64(i)
                chain.consume(input) { _ in done.fulfill() }
            }
            try waitForPending(processor, count: 4)
            order.forEach(processor.complete)
            wait(for: [done], timeout: 3)
            XCTAssertEqual(values.values, [0, 1, 2, 3], "完成排列：\(order)")
        }
    }
    func testTimeoutAdvancesAStalledOrderingWindowAndRejectsLateResult() throws {
        let processor = Round2DeferredProcessor()
        let values = Round2LockedValues()
        let done = expectation(description: "超时释放排序窗口"); done.expectedFulfillmentCount = 2
        let chain = MediaProcessorChain(processors: [processor], sinks: [PixelBufferSink { values.append(Int($0.metadata.frameIndex!)) }])
        chain.node.processorNode.frameProcessingTimeout = 0.05
        for i in 0..<2 { chain.consume(try Round2Fixtures.frame(i)) { _ in done.fulfill() } }
        try waitForPending(processor, count: 2)
        processor.complete(1)
        wait(for: [done], timeout: 2)
        XCTAssertEqual(values.values, [])
        processor.complete(0)
        XCTAssertEqual(values.values, [])
    }
    func testTimeoutDoesNotStartAnotherCallOnAnUnfinishedSerialProcessor() throws {
        let processor = Round2DeferredProcessor(limit: 1)
        let done = expectation(description: "状态型处理器超时后停止"); done.expectedFulfillmentCount = 2
        let chain = MediaProcessorChain(processors: [processor])
        chain.node.processorNode.frameProcessingTimeout = 0.05
        for i in 0..<2 { chain.consume(try Round2Fixtures.frame(i)) { _ in done.fulfill() } }
        try waitForPending(processor, count: 1)
        wait(for: [done], timeout: 2)
        XCTAssertEqual(processor.indices, [0])
        XCTAssertEqual(processor.peak, 1)
        processor.complete(0)
    }
    func testSustainedBacklogReleasesAlreadyProcessedQueueStorage() throws {
        let processor = Round2DeferredProcessor(limit: 1)
        let chain = MediaProcessorChain(processors: [processor])
        let done = expectation(description: "长期背压队列排空"); done.expectedFulfillmentCount = 150
        let frame = try Round2Fixtures.frame(0)
        for i in 0..<150 {
            var input = frame; input.metadata.frameIndex = Int64(i)
            chain.consume(input) { _ in done.fulfill() }
        }
        for i in 0..<100 {
            try waitForPending(processor, count: 1)
            processor.complete(i)
        }
        try waitForPending(processor, count: 1)
        XCTAssertLessThan(chain.node.processorNode.queuedWorkStorageCount, 100)
        for i in 100..<150 { try waitForPending(processor, count: 1); processor.complete(i) }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(chain.node.processorNode.queuedWorkStorageCount, 0)
    }
    func testDeclaredSerialProcessorDoesNotReceiveConcurrentFrames() throws {
        let processor = Round2DeferredProcessor(limit: 1)
        let done = expectation(description: "串行处理完成"); done.expectedFulfillmentCount = 3
        let chain = MediaProcessorChain(processors: [processor])
        for i in 0..<3 { chain.consume(try Round2Fixtures.frame(i)) { _ in done.fulfill() } }
        for i in 0..<3 {
            try waitForPending(processor, count: 1)
            XCTAssertEqual(processor.indices, [i])
            processor.complete(i)
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(processor.peak, 1)
    }

    func testCancellationReleasesQueuedAndReorderedFramesExactlyOnce() throws {
        let processor = Round2DeferredProcessor()
        let done = expectation(description: "取消所有已接纳帧"); done.expectedFulfillmentCount = 3
        let output = Round2LockedValues()
        let chain = MediaProcessorChain(processors: [processor], sinks: [PixelBufferSink { output.append(Int($0.metadata.frameIndex!)) }])
        for i in 0..<3 { chain.consume(try Round2Fixtures.frame(i)) { _ in done.fulfill() } }
        try waitForPending(processor, count: 3)
        processor.complete(2)
        chain.cancel()
        processor.complete(0); processor.complete(1)
        wait(for: [done], timeout: 3)
        XCTAssertEqual(output.values, [])
    }

    func testAudioBypassDoesNotWaitForBlockedVideo() throws {
        let processor = Round2DeferredProcessor()
        let output = Round2LockedValues()
        let node = MediaProcessorNode(processors: [processor]); node.processesAudioFrames = false
        let source = MediaOutputNode()
        node.add(consumer: MediaSinkNode(sink: PixelBufferSink { output.append(Int($0.metadata.frameIndex!)) }))
        let done = expectation(description: "独立音视频确认"); done.expectedFulfillmentCount = 2
        node.consume(try Round2Fixtures.frame(0), from: source) { _ in done.fulfill() }
        try waitForPending(processor, count: 1)
        node.consume(try Round2Fixtures.audioFrame(99), from: source) { _ in done.fulfill() }
        XCTAssertEqual(output.values, [99])
        processor.complete(0)
        wait(for: [done], timeout: 3)
        XCTAssertEqual(output.values, [99, 0])
    }

    func testBoundedRecordingSubscriberCannotBlockPreviewHandoff() throws {
        let source = Round2Source()
        let recording = MediaSourceNodeAdapter(source: source)
        recording.deliveryPolicy = .boundedDropNewest(maximumInFlightFrames: 6)
        recording.maximumInFlightAudioFrameCount = 12
        let held = Round2HeldConsumer(); recording.add(consumer: held)
        let preview = MediaSourceNodeAdapter(source: source)
        preview.deliveryPolicy = .latestOnly; preview.acceptsAudioFrames = false
        let values = Round2LockedValues()
        preview.add(consumer: MediaSinkNode(sink: PixelBufferSink { values.append(Int($0.metadata.frameIndex!)) }))
        let output = MediaOutputNode()
        for i in 0..<20 {
            let done = expectation(description: "仅等待有界交接")
            CameraFrameDistributor.deliver(try Round2Fixtures.frame(i), source: source, delegates: [recording, preview],
                output: output, shouldContinue: { true }, completion: { done.fulfill() })
            wait(for: [done], timeout: 2)
        }
        XCTAssertEqual(held.count, 6)
        XCTAssertEqual(values.values, Array(0..<20))
        held.releaseAll()
    }

    func testUnboundedSubscriberStillHoldsSourceAcknowledgement() throws {
        let source = Round2Source()
        let delegate = Round2HeldDelegate()
        let output = MediaOutputNode()
        let done = DispatchSemaphore(value: 0)
        CameraFrameDistributor.deliver(try Round2Fixtures.frame(0), source: source, delegates: [delegate],
            output: output, shouldContinue: { true }, completion: { done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 0.02), .timedOut)
        delegate.complete?(.success(()))
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testPreviewRejectsAudioBeforeVideoProcessorsAndImageConversion() throws {
        let source = Round2Source()
        let calls = Round2LockedValues()
        let shown = expectation(description: "预览仅接纳视频")
        let processor = ClosureFrameProcessor { frame, completion in calls.append(Int(frame.metadata.frameIndex!)); completion(.success(frame)) }
        let pipeline = PreviewPipeline(source: source, processors: [processor], frameHandler: { frame in
            XCTAssertEqual(frame.metadata.frameIndex, 2); shown.fulfill()
        })
        pipeline.start()
        source.emit(try Round2Fixtures.audioFrame(99))
        source.emit(try Round2Fixtures.frame(2))
        wait(for: [shown], timeout: 2)
        XCTAssertEqual(calls.values, [2])
        pipeline.stop()
    }
    func testPreviewBranchErrorDoesNotFailRecordingDelivery() {
        let preview = PreviewSink { _, _ in XCTFail("无像素帧不能成为图像") }
        let branch = RecordingPreviewBranch(preview: preview)
        var errors = 0
        branch.errorHandler = { _ in errors += 1 }
        struct Empty: MediaFrame { var metadata = FrameMetadata(presentationTime: .zero) }
        var delivered = false
        branch.consume(Empty()) { result in if case .success = result { delivered = true } }
        XCTAssertTrue(delivered)
        XCTAssertEqual(errors, 1)
    }
    func testRecordedArtifactRetainsInputColorOrderAfterReverseCompletion() throws {
        let processor = Round2DeferredProcessor()
        let output = Round2Fixtures.url()
        defer { try? FileManager.default.removeItem(at: output) }
        let recorder = try RecorderSink(outputURL: output, configuration: .init(includesAudio: false))
        let chain = MediaProcessorChain(processors: [processor], sinks: [recorder])
        let accepted = expectation(description: "实际录制三帧"); accepted.expectedFulfillmentCount = 3
        for i in 0..<3 { chain.consume(try Round2Fixtures.frame(i)) { _ in accepted.fulfill() } }
        try waitForPending(processor, count: 3)
        processor.complete(2); processor.complete(1); processor.complete(0)
        wait(for: [accepted], timeout: 3)
        let finished = expectation(description: "实际录制完成")
        chain.finish { _ in finished.fulfill() }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(try Round2Fixtures.colors(output), [0, 1, 2])
    }
    func testSharedRecordingRunsOnceAndDoesNotWaitForSuspendedPreview() throws {
        let source = Round2Source()
        let calls = Round2LockedValues()
        let processor = ClosureFrameProcessor { frame, completion in calls.append(Int(frame.metadata.frameIndex!)); completion(.success(frame)) }
        let queue = DispatchQueue(label: "round2.slow-preview"); queue.suspend()
        let shown = expectation(description: "预览只交付最后一帧")
        let preview = PreviewSink(callbackQueue: queue, frameHandler: { frame in
            XCTAssertEqual(frame.metadata.frameIndex, 2); shown.fulfill()
        })
        let url = Round2Fixtures.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = try RecordingPipeline(source: source, outputURL: url, processors: [processor],
            recorderConfiguration: .init(includesAudio: false), sharingPreview: preview)
        pipeline.start()
        for i in 0..<3 { source.emit(try Round2Fixtures.frame(i)) }
        let done = expectation(description: "录制不等待UI")
        pipeline.stop { result in if case .failure(let error) = result { XCTFail(String(describing: error)) }; done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(calls.values, [0, 1, 2])
        XCTAssertEqual(pipeline.recorderSink.state, .finished)
        queue.resume()
        wait(for: [shown], timeout: 2)
    }

    private func waitForPending(_ processor: Round2DeferredProcessor, count: Int) throws {
        let end = Date().addingTimeInterval(3)
        while processor.indices.count < count && Date() < end { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertEqual(processor.indices.count, count)
    }
}

final class Round2LockedValues: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [Int] = []
    func append(_ value: Int) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return storage }
}
final class Round2DeferredProcessor: FrameProcessor, FrameProcessorCapabilityProviding, @unchecked Sendable {
    let capabilities: FrameProcessorCapabilities
    private let lock = NSLock()
    private var pending: [Int: (MediaFrame, (Result<MediaFrame, Error>) -> Void)] = [:]
    private var highWater = 0
    init(limit: Int? = nil) { capabilities = FrameProcessorCapabilities(maximumConcurrentFrameCount: limit) }
    var indices: [Int] { lock.lock(); defer { lock.unlock() }; return pending.keys.sorted() }
    var peak: Int { lock.lock(); defer { lock.unlock() }; return highWater }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        lock.lock(); pending[Int(frame.metadata.frameIndex!)] = (frame, completion); highWater = max(highWater, pending.count); lock.unlock()
    }
    func complete(_ index: Int) { lock.lock(); let item = pending.removeValue(forKey: index); lock.unlock(); item?.1(.success(item!.0)) }
}
final class Round2Source: MediaSource {
    weak var delegate: MediaSourceDelegate?
    func start() {}
    func pause() {}
    func resume() {}
    func stop() { delegate?.mediaSourceDidFinish(self) }
    func cancel() {}
    func emit(_ frame: MediaFrame) { delegate?.mediaSource(self, didOutput: frame, completion: { _ in }) }
}
private final class Round2HeldConsumer: MediaFrameConsumerNode {
    private var callbacks: [(Result<Void, Error>) -> Void] = []
    var count: Int { callbacks.count }
    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) { callbacks.append(completion) }
    func releaseAll() { let copy = callbacks; callbacks.removeAll(); copy.forEach { $0(.success(())) } }
}
private final class Round2HeldDelegate: MediaSourceDelegate {
    var complete: ((Result<Void, Error>) -> Void)?
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) { complete = completion }
}
#endif
