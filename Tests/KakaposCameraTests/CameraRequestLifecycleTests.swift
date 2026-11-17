// 作者：Condy
import XCTest
import KakaposMediaCore
@testable import KakaposCamera

final class CameraRequestLifecycleTests: XCTestCase {
    private enum Failure: Error { case processing, final, timeout }

    func testPhotoSuccessWaitsForFinalBoundaryAndOnlyFinishesOnce() throws {
        let state = CameraPhotoRequestResult<Int>()
        state.stage(.success(42))
        XCTAssertEqual(try state.finish()?.get(), 42)
        XCTAssertNil(state.finish())
        state.stage(.success(99))
        XCTAssertNil(state.finish(error: Failure.final))
    }

    func testPhotoFinalErrorOverridesProcessedSuccess() {
        let state = CameraPhotoRequestResult<Int>()
        state.stage(.success(42))
        guard case .failure(Failure.final)? = state.finish(error: Failure.final) else { return XCTFail("最终错误必须交付") }
        XCTAssertNil(state.finish())
    }

    func testPhotoProcessingFailureAndMissingResourceRemainFailures() {
        let state = CameraPhotoRequestResult<Int>()
        state.stage(.failure(Failure.processing))
        state.stage(.success(42))
        guard case .failure(Failure.processing)? = state.finish() else { return XCTFail("处理错误不能被覆盖") }
        guard case .failure(CameraPhotoCaptureError.missingResource)? = CameraPhotoRequestResult<Int>().finish() else { return XCTFail("空结果不能成功") }
    }

    func testPhotoTimeoutRacesFinalCallbackWithOneResult() {
        for _ in 0..<100 {
            let state = CameraPhotoRequestResult<Int>()
            state.stage(.success(42))
            let delivered = LockedCounter()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if state.finish(error: index == 0 ? Failure.timeout : nil) != nil { delivered.increment() }
            }
            XCTAssertEqual(delivered.value, 1)
        }
    }

    func testCancellationBeforeContinuationAndRegistrationIsImmediate() async {
        let task = CameraPhotoTask<Int>()
        task.cancel()
        let cleanup = LockedCounter()
        task.onCancel { cleanup.increment() }
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(task.begin(continuation))
            }
            XCTFail("取消应抛错")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cleanup.value, 1)
        XCTAssertFalse(task.finish(.success(42)))
    }

    func testCancellationAfterRegistrationReleasesWaiterAndCleanupOnce() async {
        let task = CameraPhotoTask<Int>()
        let cleanup = LockedCounter()
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                XCTAssertTrue(task.begin(continuation))
                task.onCancel { cleanup.increment() }
                task.cancel()
                task.cancel()
            }
            XCTFail("取消应抛错")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cleanup.value, 1)
        XCTAssertFalse(task.finish(.success(42)))
    }

    func testSuccessfulTaskIgnoresLateCancellation() async throws {
        let task = CameraPhotoTask<Int>()
        let cleanup = LockedCounter()
        let value: Int = try await withCheckedThrowingContinuation { continuation in
            XCTAssertTrue(task.begin(continuation))
            task.onCancel { cleanup.increment() }
            XCTAssertTrue(task.finish(.success(42)))
            task.cancel()
        }
        XCTAssertEqual(value, 42)
        XCTAssertFalse(task.isCancelled)
        XCTAssertEqual(cleanup.value, 0)
    }

    func testTaskFinishAndCancellationRaceOnlyResolveOnce() async {
        for _ in 0..<100 {
            let task = CameraPhotoTask<Int>()
            let cleanup = LockedCounter()
            do {
                let value: Int = try await withCheckedThrowingContinuation { continuation in
                    XCTAssertTrue(task.begin(continuation))
                    task.onCancel { cleanup.increment() }
                    DispatchQueue.concurrentPerform(iterations: 2) { index in
                        if index == 0 { task.finish(.success(42)) } else { task.cancel() }
                    }
                }
                XCTAssertEqual(value, 42)
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertLessThanOrEqual(cleanup.value, 1)
        }
    }

    func testPositionSwitchPreservesIdleStoppedPausedAndRunningState() {
        let setups: [[CameraLifecycleAction]] = [[], [.didStartRunning], [.didStartRunning, .pauseRequested], [.didStartRunning, .didStopRunning]]
        for setup in setups {
            for fails in [false, true] {
                var state = CameraSessionLifecycle(position: .back)
                setup.forEach { state.handle($0) }
                let before = state.state
                state.handle(.positionSwitchRequested(.front))
                if fails { state.handle(.runtimeError(isRecoverable: true, description: "回滚")) }
                state.handle(.positionChanged(fails ? .back : .front))
                XCTAssertEqual(state.state, before)
            }
        }
    }

    func testLatePositionResultCannotReviveTerminalState() {
        for terminal in [CameraLifecycleAction.didStopRunning, .runtimeError(isRecoverable: false, description: "失败"), .authorizationChanged(.denied)] {
            var state = CameraSessionLifecycle(position: .back)
            state.handle(.didStartRunning)
            state.handle(.positionSwitchRequested(.front))
            state.handle(terminal)
            let before = state.state
            state.handle(.positionChanged(.front))
            XCTAssertEqual(state.state, before)
        }
    }

    func testEmptyAndBoundedOnlyRoutesCompleteWithoutQueueHop() {
        for bounded in [false, true] {
            let source = RouteSource()
            let delegate = RouteDelegate(bounded: true)
            var done = false
            CameraFrameDistributor.deliver(RouteFrame(), source: source,
                delegates: bounded ? [delegate] : [], output: MediaOutputNode(), shouldContinue: { true }) { done = true }
            XCTAssertTrue(done)
            XCTAssertEqual(delegate.calls, bounded ? 1 : 0)
        }
    }

    func testUncontrolledRouteWaitsForOneAcknowledgementAndOutputAddedDuringDelivery() {
        let source = RouteSource()
        let output = MediaOutputNode()
        let consumer = RouteConsumer()
        let delegate = RouteDelegate(bounded: false)
        delegate.onFrame = { output.add(consumer: consumer) }
        let done = expectation(description: "非受控路线收口")
        let count = LockedCounter()
        CameraFrameDistributor.deliver(RouteFrame(), source: source,
            delegates: [delegate], output: output, shouldContinue: { true }) { count.increment(); done.fulfill() }
        XCTAssertEqual(consumer.calls, 1)
        XCTAssertEqual(count.value, 0)
        delegate.ack?(.success(()))
        delegate.ack?(.success(()))
        XCTAssertEqual(count.value, 0)
        consumer.ack?(.success(()))
        consumer.ack?(.success(()))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(count.value, 1)
    }

    func testCancelledDistributionDoesNotInvokeRoutes() {
        let delegate = RouteDelegate(bounded: false)
        let consumer = RouteConsumer()
        let output = MediaOutputNode()
        output.add(consumer: consumer)
        let done = expectation(description: "已取消分发")
        CameraFrameDistributor.deliver(RouteFrame(), source: RouteSource(),
            delegates: [delegate], output: output, shouldContinue: { false }) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(delegate.calls, 0)
        XCTAssertEqual(consumer.calls, 0)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() { lock.lock(); stored += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
private final class RouteSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    func start() {}
    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}
private final class RouteDelegate: MediaSourceDelegate, BoundedMediaSourceDelegate {
    let managesFrameBackpressure: Bool
    var calls = 0
    var ack: ((Result<Void, Error>) -> Void)?
    var onFrame: (() -> Void)?
    init(bounded: Bool) { managesFrameBackpressure = bounded }
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        calls += 1
        onFrame?()
        ack = completion
    }
}
private final class RouteConsumer: MediaFrameConsumerNode {
    var calls = 0
    var ack: ((Result<Void, Error>) -> Void)?
    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        calls += 1
        ack = completion
    }
}

private struct RouteFrame: MediaFrame { var metadata = FrameMetadata(presentationTime: .zero) }
