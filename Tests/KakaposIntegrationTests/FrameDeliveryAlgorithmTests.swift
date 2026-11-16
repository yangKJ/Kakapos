// 作者：Condy
#if os(macOS)
import AVFoundation
import CoreGraphics
import XCTest
@testable import KakaposMediaCore
@testable import KakaposVideo

final class FrameDeliveryAlgorithmTests: XCTestCase {
    private func buffer() throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32BGRA, nil, &output), kCVReturnSuccess)
        return try XCTUnwrap(output)
    }
    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
    func testPreviewCoalescesBeforeImageConversion() throws {
        let queue = DispatchQueue(label: "preview.conversion-test")
        queue.suspend()
        let delivered = expectation(description: "最新帧完成")
        let sink = PreviewSink(callbackQueue: queue) { _, metadata in
            XCTAssertEqual(metadata.frameIndex, 99)
            delivered.fulfill()
        }
        let pixelBuffer = try buffer()
        for i in 0..<100 {
            sink.consume(PixelBufferFrame(pixelBuffer: pixelBuffer, metadata: .init(presentationTime: .zero, frameIndex: Int64(i)))) { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
            }
        }
        XCTAssertEqual(sink.snapshot.lastImageWidth, 8)
        XCTAssertEqual(sink.conversionCountsForTesting.converted, 0)
        XCTAssertEqual(sink.conversionCountsForTesting.coalesced, 99)
        queue.resume()
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(sink.conversionCountsForTesting.converted, 1)
    }
    func testAcceptedPreviewFinishesAfterCallerReleasesSink() throws {
        let queue = DispatchQueue(label: "preview.accepted-lifetime-test")
        queue.suspend()
        let delivered = expectation(description: "已接纳帧仍可显示")
        let acknowledged = expectation(description: "已接纳帧仍会确认")
        var sink: PreviewSink? = PreviewSink(callbackQueue: queue) { _, _ in delivered.fulfill() }
        weak var weakSink = sink
        sink?.consume(PixelBufferFrame(pixelBuffer: try buffer(), metadata: .init(presentationTime: .zero))) { _ in acknowledged.fulfill() }
        sink = nil
        queue.resume()
        wait(for: [delivered, acknowledged], timeout: 2)
        queue.sync {}
        XCTAssertNil(weakSink, "交付完成后不应继续保留接收器")
    }
    func testNativeFramePreviewDoesNotMaterializeImages() {
        let delivered = expectation(description: "原生帧完成")
        let sink = PreviewSink(frameHandler: { frame in
            XCTAssertEqual(frame.metadata.frameIndex, 7)
            delivered.fulfill()
        })
        sink.consume(OnlyMetadataFrame(metadata: .init(presentationTime: .zero, frameIndex: 7))) { _ in }
        wait(for: [delivered], timeout: 2)
        XCTAssertNil(sink.snapshot.lastImageWidth)
        XCTAssertEqual(sink.conversionCountsForTesting.converted, 0)
    }
    func testFinishWaitsForLatestPreviewAndAcknowledgesOnce() throws {
        let queue = DispatchQueue(label: "preview.finish-test")
        queue.suspend()
        let delivered = expectation(description: "画面回调")
        let acknowledged = expectation(description: "帧确认")
        let finished = expectation(description: "收尾完成")
        let sink = PreviewSink(callbackQueue: queue) { _, _ in delivered.fulfill() }
        sink.consume(PixelBufferFrame(pixelBuffer: try buffer(), metadata: .init(presentationTime: .zero))) { _ in acknowledged.fulfill() }
        sink.finish { _ in finished.fulfill() }
        XCTAssertEqual(sink.state, .active)
        queue.resume()
        wait(for: [delivered, acknowledged, finished], timeout: 2, enforceOrder: true)
        XCTAssertEqual(sink.state, .finished)
    }
    func testCancelledPreviewAcknowledgesPendingFrameWithoutConversion() throws {
        let queue = DispatchQueue(label: "preview.cancel-test")
        queue.suspend()
        let acknowledged = expectation(description: "取消确认")
        let sink = PreviewSink(callbackQueue: queue) { _, _ in XCTFail("取消后不可显示") }
        sink.consume(PixelBufferFrame(pixelBuffer: try buffer(), metadata: .init(presentationTime: .zero))) { _ in acknowledged.fulfill() }
        sink.cancel()
        queue.resume()
        wait(for: [acknowledged], timeout: 2)
        XCTAssertEqual(sink.conversionCountsForTesting.converted, 0)
    }
    func testImageSourceIsBoundedAndWaitsForEveryAcknowledgement() throws {
        let source = ImageSource(frames: Array(repeating: StillImageFrame(image: try image()), count: 2), callbackQueue: .global(), maximumInFlightFrameCount: 2)
        let received = expectation(description: "两帧进入下游")
        received.expectedFulfillmentCount = 2
        let finished = expectation(description: "确认后完成")
        let delegate = HeldImageDelegate(received: received, finished: finished)
        source.delegate = delegate
        source.start()
        wait(for: [received], timeout: 2)
        XCTAssertEqual(source.sourceSnapshot.details["inFlightFrames"], "2")
        XCTAssertEqual(source.sourceSnapshot.details["peakInFlightFrames"], "2")
        XCTAssertEqual(source.sourceSnapshot.details["rasterizationCount"], "1")
        XCTAssertFalse(delegate.didFinish)
        delegate.acknowledge(1)
        XCTAssertFalse(delegate.didFinish)
        delegate.acknowledge(0)
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(source.sourceSnapshot.details["inFlightFrames"], "0")
    }
    func testStaticImageCacheNeverSharesMutableTemplatesWithProcessors() throws {
        let source = ImageSource(frames: Array(repeating: StillImageFrame(image: try image()), count: 2), callbackQueue: .global(), maximumInFlightFrameCount: 1)
        let done = expectation(description: "静帧缓存隔离")
        let delegate = MutatingImageDelegate(done: done)
        source.delegate = delegate
        source.start()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(source.sourceSnapshot.details["rasterizationCount"], "1")
        XCTAssertLessThanOrEqual(Int(source.sourceSnapshot.details["cachedImageBytes"] ?? "0") ?? 0, source.imageCacheBudgetBytes)
    }
    func testAdaptivePolicyDoesNotOscillateAtConstantLoad() {
        let policy = VideoPreviewAdaptivePolicy()
        var fps = 30
        var under = 0
        var history: [Int] = []
        for _ in 0..<100 {
            if 0.04 <= policy.overloadBudgetRatio / Double(fps) { under += 1 } else { under = 0 }
            let next = policy.recommendation(currentFramesPerSecond: fps, processingDuration: 0.04, consecutiveUnderBudgetSamples: under)
            if next > fps { under = 0 }
            fps = next
            history.append(fps)
        }
        XCTAssertTrue(history.dropFirst(2).allSatisfy { $0 == 20 })
        XCTAssertEqual(policy.recommendation(currentFramesPerSecond: 20, processingDuration: 0.005, consecutiveUnderBudgetSamples: 24), 25)
    }
    func testPreviewLanePreservesSourceReceiptClockAcrossMetadataReplacement() throws {
        let delivered = expectation(description: "处理后保留源接收时钟")
        let processor = ClosureFrameProcessor { frame, completion in
            completion(.success(PixelBufferFrame(pixelBuffer: extractPixelBuffer(frame)!, metadata: .init(presentationTime: .zero))))
        }
        let plan = FrameProcessingPlan(identity: .init(identifier: "clock", revision: "1"), makeProcessors: { [processor] })
        let lane = try VideoPreviewProcessingLane(generation: .init(rawValue: 1), mode: .processed(plan)) { frame, _, _ in
            XCTAssertEqual(frame.metadata.receivedHostTimeSeconds, 42)
            delivered.fulfill()
        }
        lane.consume(PixelBufferFrame(pixelBuffer: try buffer(), metadata: .init(presentationTime: .zero, receivedHostTimeSeconds: 42)))
        wait(for: [delivered], timeout: 2)
        lane.cancel()
    }
    func testPreviewCancellationBeforeOperationInstallationDoesNotBlock() throws {
        let started = expectation(description: "处理器开始创建句柄")
        let cancelled = expectation(description: "迟到的句柄立即取消")
        let processor = DelayedOperationProcessor(started: started, cancelled: cancelled)
        let plan = FrameProcessingPlan(identity: .init(identifier: "delayed", revision: "1"), makeProcessors: { [processor] })
        let lane = try VideoPreviewProcessingLane(generation: .init(rawValue: 1), mode: .processed(plan)) { _, _, _ in
            XCTFail("取消后不可交付画面")
        }
        lane.consume(PixelBufferFrame(pixelBuffer: try buffer(), metadata: .init(presentationTime: .zero)))
        wait(for: [started], timeout: 2)
        lane.cancel()
        XCTAssertTrue(lane.performanceSnapshot.isFinal)
        processor.allowReturn.signal()
        wait(for: [cancelled], timeout: 2)
    }
    func testPresentationStatisticsFreezeOnCancellation() {
        let stats = VideoPreviewPerformanceAccumulator()
        stats.recordPresentation(duration: 0.02)
        stats.recordPresentation(duration: 0.04)
        stats.markFinal(hadInFlightFrame: false)
        stats.recordPresentation(duration: 1)
        XCTAssertEqual(stats.snapshot.presentedFrameCount, 2)
        XCTAssertEqual(stats.snapshot.averagePresentationLatency, 0.03, accuracy: 0.00001)
        XCTAssertEqual(stats.snapshot.maximumPresentationLatency, 0.04)
    }
}
private final class DelayedOperationProcessor: CancellableFrameProcessor, @unchecked Sendable {
    let allowReturn = DispatchSemaphore(value: 0)
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation
    init(started: XCTestExpectation, cancelled: XCTestExpectation) { self.started = started; self.cancelled = cancelled }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        _ = processCancellable(frame, completion: completion)
    }
    func processCancellable(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) -> FrameProcessingOperation {
        started.fulfill()
        allowReturn.wait()
        return FrameProcessingCancellation { self.cancelled.fulfill() }
    }
}
private struct OnlyMetadataFrame: MediaFrame { var metadata: FrameMetadata }
private final class HeldImageDelegate: MediaSourceDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [(Result<Void, Error>) -> Void] = []
    private var finished = false
    private let received: XCTestExpectation
    private let finishedExpectation: XCTestExpectation
    init(received: XCTestExpectation, finished: XCTestExpectation) { self.received = received; self.finishedExpectation = finished }
    var didFinish: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock(); completions.append(completion); lock.unlock()
        received.fulfill()
    }
    func acknowledge(_ index: Int) { lock.lock(); let callback = completions[index]; lock.unlock(); callback(.success(())) }
    func mediaSourceDidFinish(_ source: MediaSource) {
        lock.lock(); finished = true; lock.unlock()
        finishedExpectation.fulfill()
    }
}
private final class MutatingImageDelegate: MediaSourceDelegate {
    private var count = 0
    private let done: XCTestExpectation
    init(done: XCTestExpectation) { self.done = done }
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let buffer = extractPixelBuffer(frame) else { XCTFail("静帧缓冲缺失"); completion(.success(())); return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(bytes[2], 255)
        bytes[2] = 17
        CVPixelBufferUnlockBaseAddress(buffer, [])
        count += 1
        completion(.success(()))
    }
    func mediaSourceDidFinish(_ source: MediaSource) { XCTAssertEqual(count, 2); done.fulfill() }
}
#endif
