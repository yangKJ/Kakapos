//
//  RuntimeContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import AudioToolbox
import CoreMedia
import CoreVideo
import XCTest

@testable import KakaposMediaCore

final class RuntimeContractTests: XCTestCase {
    func testStopCompletionIsDeliveredOnMainThreadAndOnlyOnce() {
        let pipeline = MediaPipeline(source: ContractSource(), processors: [], sinks: [])
        let expectation = expectation(description: "stop completion")
        expectation.expectedFulfillmentCount = 2
        var callbackCount = 0
        var onMain = false

        pipeline.stop { result in
            callbackCount += 1
            onMain = Thread.isMainThread
            XCTAssertTrue((try? result.get()) != nil)
            expectation.fulfill()
        }
        pipeline.stop { _ in
            callbackCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(callbackCount, 2)
        XCTAssertTrue(onMain)
    }

    func testStopDrainsAnAlreadyAcceptedLastFrameBeforeCompletion() {
        let source = ContractSource()
        let processorFinished = expectation(description: "processor completion")
        let sinkReceived = expectation(description: "sink receives final frame")
        let processor = ClosureFrameProcessor { frame, completion in
            DispatchQueue.global().async {
                processorFinished.fulfill()
                completion(.success(frame))
            }
        }
        let sink = ContractSink { _ in sinkReceived.fulfill() }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
        pipeline.start()
        source.emit(frameIndex: 1)

        let stopped = expectation(description: "pipeline drained")
        pipeline.stop { result in
            XCTAssertTrue((try? result.get()) != nil)
            stopped.fulfill()
        }

        wait(for: [processorFinished, sinkReceived, stopped], timeout: 2)
    }

    func testProcessorCompletionIsIdempotent() {
        let source = ContractSource()
        let sink = ContractSink { _ in }
        let processor = ClosureFrameProcessor { frame, completion in
            completion(.success(frame))
            completion(.success(frame))
        }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
        pipeline.start()
        source.emit(frameIndex: 2)
        let stopped = expectation(description: "idempotent completion stop")
        pipeline.stop { _ in stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
        XCTAssertEqual(pipeline.state, .finished)
    }

    func testProcessorCapabilityRejectsUnsupportedFrameBeforeProcessing() {
        let source = ContractSource()
        let processor = CapabilityLimitedProcessor()
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [])
        pipeline.start()
        source.emit(frameIndex: 3)
        let stopped = expectation(description: "unsupported format rejected")
        pipeline.stop { result in
            if case .success = result { XCTFail("不支持的格式必须失败") }
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(processor.calls, 0)
    }

    func testCancelCancelsInFlightProcessorAndLateResultDoesNotReachSink() {
        let source = ContractSource()
        let processor = DeferredProcessor()
        let started = expectation(description: "处理器已启动")
        processor.started = { started.fulfill() }
        let sink = ContractSink { _ in XCTFail("late result reached sink") }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
        pipeline.start()
        source.emit(frameIndex: 4)
        wait(for: [started], timeout: 2)
        pipeline.cancel()
        XCTAssertEqual(processor.cancelled, 1)
        processor.callback?(
            .success(PixelBufferFrame(pixelBuffer: makeBuffer(), metadata: FrameMetadata(presentationTime: .zero))))
        XCTAssertEqual(sink.consumed, 0)
    }

    func testSinkFinishFailurePublishesFailedResult() {
        let failure = NSError(domain: "RuntimeContractTests", code: 1)
        let sink = FailingFinishSink(error: failure)
        let pipeline = MediaPipeline(source: ContractSource(), processors: [], sinks: [sink])
        let stopped = expectation(description: "finish failure")
        pipeline.stop { result in
            guard case .failure(let error) = result else {
                return XCTFail("sink finish failure must propagate")
            }
            XCTAssertEqual((error as NSError).domain, failure.domain)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 1)
        XCTAssertEqual(pipeline.state, .failed)
    }

    func testConcurrentStopAndCancelResolvesStopOnce() {
        let pipeline = MediaPipeline(source: ContractSource(), processors: [], sinks: [])
        let stopped = expectation(description: "stop completion")
        stopped.expectedFulfillmentCount = 1
        pipeline.start()
        DispatchQueue.global().async { pipeline.stop { _ in stopped.fulfill() } }
        DispatchQueue.global().async { pipeline.cancel() }
        wait(for: [stopped], timeout: 1)
        XCTAssertTrue([.finished, .cancelled].contains(pipeline.state))
    }

    func testProcessorAndSinkReplacementAffectsSubsequentFrame() {
        let source = ContractSource()
        let first = ContractSink { _ in }
        let second = ContractSink { _ in }
        let firstProcessor = TaggingProcessor(tag: 1)
        let secondProcessor = TaggingProcessor(tag: 2)
        let pipeline = MediaPipeline(source: source, processors: [firstProcessor], sinks: [first])
        pipeline.start()
        source.emit(frameIndex: 1)
        pipeline.processors = [secondProcessor]
        pipeline.sinks = [second]
        source.emit(frameIndex: 2)
        let stopped = expectation(description: "replacement stop")
        pipeline.stop { _ in stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
        XCTAssertEqual(firstProcessor.calls, 1)
        XCTAssertEqual(secondProcessor.calls, 1)
        XCTAssertEqual(first.consumed, 1)
        XCTAssertEqual(second.consumed, 1)
    }

    func testSourceAdapterFinishWaitsForBothVideoAndAudioAcknowledgements() throws {
        let source = ContractSource()
        let adapter = MediaSourceNodeAdapter(source: source)
        adapter.maximumInFlightAudioFrameCount = 2
        let consumer = DeferredDeliveryConsumer()
        adapter.add(consumer: consumer)
        var finishes = 0
        adapter.finishHandler = { finishes += 1 }
        let video = PixelBufferFrame(pixelBuffer: makeBuffer(), metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        adapter.mediaSource(source, didOutput: video)
        adapter.mediaSource(source, didOutput: try makeDeliveryAudioFrame())
        adapter.mediaSourceDidFinish(source)

        consumer.complete(frameIndex: 1)
        XCTAssertEqual(finishes, 0, "音频尚未确认时不能完成 source")
        consumer.complete(frameIndex: 100)
        XCTAssertEqual(finishes, 1)
    }

    func testAudioAcknowledgementDoesNotReleasePendingLatestVideo() throws {
        let source = ContractSource()
        let adapter = MediaSourceNodeAdapter(source: source)
        adapter.deliveryPolicy = .latestOnly
        adapter.maximumInFlightAudioFrameCount = 2
        let consumer = DeferredDeliveryConsumer()
        adapter.add(consumer: consumer)
        for index in 1...2 {
            let video = PixelBufferFrame(pixelBuffer: makeBuffer(), metadata: FrameMetadata(presentationTime: .zero, frameIndex: Int64(index)))
            adapter.mediaSource(source, didOutput: video)
        }
        adapter.mediaSource(source, didOutput: try makeDeliveryAudioFrame())

        consumer.complete(frameIndex: 100)
        XCTAssertEqual(consumer.indices, [1, 100], "音频确认不能增加在途视频数")
        consumer.complete(frameIndex: 1)
        XCTAssertEqual(consumer.indices, [1, 100, 2])
        consumer.complete(frameIndex: 2)
    }

}

private final class ContractSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    func start() {}
    func pause() {}
    func resume() {}
    func stop() { delegate?.mediaSourceDidFinish(self) }
    func cancel() {}

    func emit(frameIndex: Int64) {
        let frame = FrameMetadata(presentationTime: .zero, frameIndex: frameIndex)
        var metadata = frame
        metadata.format = FrameFormat(
            pixelFormat: .yuv420BiPlanar10BitVideoRange,
            colorInfo: FrameColorInfo(primaries: .bt2020, transferFunction: .hlg, yCbCrMatrix: .bt2020),
            dynamicRange: .hdr(.hlg))
        delegate?.mediaSource(self, didOutput: PixelBufferFrame(pixelBuffer: makeBuffer(), metadata: metadata))
    }

    private func makeBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }
}

private class ContractSink: MediaSink {
    private let handler: (MediaFrame) -> Void
    init(handler: @escaping (MediaFrame) -> Void) { self.handler = handler }
    private(set) var consumed = 0
    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        consumed += 1
        handler(frame)
        completion(.success(()))
    }
}

private final class FailingFinishSink: MediaSink {
    private let error: Error
    init(error: Error) { self.error = error }
    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) { completion(.success(())) }
    func finish(completion: @escaping (Result<Void, Error>) -> Void) { completion(.failure(error)) }
}

private final class CapabilityLimitedProcessor: FrameProcessor, FrameProcessorCapabilityProviding {
    let capabilities = FrameProcessorCapabilities(acceptedPixelFormats: [.yuv420BiPlanar10BitVideoRange])
    private(set) var calls = 0
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        calls += 1
        completion(.success(frame))
    }
}

private final class DeferredProcessor: CancellableFrameProcessor {
    private(set) var cancelled = 0
    var callback: ((Result<MediaFrame, Error>) -> Void)?
    var started: (() -> Void)?
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        callback = completion
    }
    func processCancellable(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void)
        -> FrameProcessingOperation
    {
        callback = completion
        started?()
        return FrameProcessingCancellation { [weak self] in self?.cancelled += 1 }
    }
}

private func makeBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
    return buffer!
}

private final class TaggingProcessor: FrameProcessor {
    let tag: Int
    private(set) var calls = 0
    init(tag: Int) { self.tag = tag }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        calls += 1
        completion(.success(frame))
    }
}


private final class DeferredDeliveryConsumer: MediaFrameConsumerNode {
    private(set) var indices: [Int64] = []
    private var completions: [Int64: (Result<Void, Error>) -> Void] = [:]

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let index = frame.metadata.frameIndex else { return XCTFail("测试帧缺少索引") }
        indices.append(index)
        completions[index] = completion
    }

    func complete(frameIndex: Int64) {
        completions.removeValue(forKey: frameIndex)?(.success(()))
    }
}

private func makeDeliveryAudioFrame() throws -> SampleBufferFrame {
    var description = AudioStreamBasicDescription(
        mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
        mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    XCTAssertEqual(CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil,
        formatDescriptionOut: &format), noErr)
    var block: CMBlockBuffer?
    XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
        allocator: nil, memoryBlock: nil, blockLength: 2, blockAllocator: nil,
        customBlockSource: nil, offsetToData: 0, dataLength: 2, flags: 0,
        blockBufferOut: &block), kCMBlockBufferNoErr)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sampleSize = 2
    var sample: CMSampleBuffer?
    XCTAssertEqual(CMSampleBufferCreateReady(
        allocator: nil, dataBuffer: try XCTUnwrap(block), formatDescription: try XCTUnwrap(format),
        sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample), noErr)
    return SampleBufferFrame(sampleBuffer: try XCTUnwrap(sample), metadata: FrameMetadata(presentationTime: .zero, frameIndex: 100))
}
