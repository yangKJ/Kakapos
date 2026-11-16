//
//  CameraRuntimeRegressionTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import XCTest

@testable import KakaposCamera

final class CameraRuntimeRegressionTests: XCTestCase {
    func testIngressCapacitySeparatesAudioAndVideoDrops() {
        let gate = CameraFrameIngressGate(maximumInFlightFrameCount: 1, maximumInFlightAudioFrameCount: 1)
        gate.reset()
        XCTAssertNotNil(gate.admit(mediaKind: .video, branchCount: 1))
        XCTAssertNotNil(gate.admit(mediaKind: .audio, branchCount: 1))
        XCTAssertNil(gate.admit(mediaKind: .video, branchCount: 1))
        XCTAssertEqual(gate.snapshot.droppedVideoFrameCount, 1)
        XCTAssertEqual(gate.snapshot.droppedAudioFrameCount, 0)
    }
    func testLateInterruptionNotificationsCannotResurrectTerminalStates() {
        for terminal: CameraLifecycleAction in [.didStopRunning, .runtimeError(isRecoverable: false, description: "failure"), .authorizationChanged(.denied)] {
            var state = CameraSessionLifecycle(position: .back)
            state.handle(.didStartRunning)
            state.handle(.wasInterrupted)
            state.handle(terminal)
            let expected = state.state
            XCTAssertNil(state.handle(.interruptionEnded))
            XCTAssertNil(state.handle(.wasInterrupted))
            XCTAssertNil(state.handle(.wasInterruptedWhileRecording))
            XCTAssertEqual(state.state, expected)
        }
    }

    func testDuplicateInterruptionPreservesOriginalPauseAndNormalRecovery() {
        for paused in [false, true] {
            var state = CameraSessionLifecycle(position: .back)
            state.handle(.didStartRunning)
            if paused { state.handle(.pauseRequested) }
            XCTAssertEqual(state.handle(.wasInterruptedWhileRecording), .wasInterruptedWhileRecording)
            XCTAssertNil(state.handle(.wasInterrupted))
            XCTAssertNil(state.handle(.wasInterruptedWhileRecording))
            XCTAssertEqual(state.handle(.interruptionEnded), .interruptionEnded)
            XCTAssertEqual(state.state, paused ? .paused : .running)
            XCTAssertNil(state.handle(.interruptionEnded))
        }
    }

    func testFailureHandoffRejectsOldFramesAndRestartsOnlyAfterBothBarriers() throws {
        for callbackFirst in [false, true] {
            let ingress = CameraFrameIngressGate(maximumInFlightFrameCount: 1)
            var run = CameraRunLifecycle()
            let original = try XCTUnwrap(run.begin { ingress.reset() })
            let oldFrame = try XCTUnwrap(ingress.admit(mediaKind: .video, branchCount: 1))
            XCTAssertNil(run.begin { ingress.reset() })
            let terminal = try XCTUnwrap(run.beginTerminal { ingress.rejectFurtherFrames() })
            XCTAssertFalse(run.isCurrent(original))
            XCTAssertFalse(ingress.isCurrentGeneration(original))
            XCTAssertNil(ingress.admit(mediaKind: .video, branchCount: 1))
            XCTAssertNil(run.beginTerminal {
                XCTFail("终态只能接管一次")
                return 99
            })
            run.expectStop(generation: terminal)
            XCTAssertTrue(run.deferStartIfStopping())
            XCTAssertNil(run.begin { ingress.reset() })
            if callbackFirst {
                XCTAssertFalse(run.markCallbackDelivered())
                XCTAssertTrue(run.isStopping)
                let result = run.consumeExpectedStop()
                XCTAssertTrue(result.consumed)
                XCTAssertTrue(result.restart)
            } else {
                let result = run.consumeExpectedStop()
                XCTAssertTrue(result.consumed)
                XCTAssertFalse(result.restart)
                XCTAssertTrue(run.isStopping)
                XCTAssertTrue(run.markCallbackDelivered())
            }
            XCTAssertFalse(run.markCallbackDelivered())
            let retry = try XCTUnwrap(run.begin { ingress.reset() })
            XCTAssertNotEqual(retry, original)
            ingress.completeBranch(for: oldFrame)
            XCTAssertTrue(run.isCurrent(retry))
            XCTAssertNotNil(ingress.admit(mediaKind: .video, branchCount: 1))
        }
    }

    func testFailureWithoutRunningSessionDoesNotWaitForAbsentStopNotification() throws {
        var run = CameraRunLifecycle()
        _ = run.begin { 1 }
        XCTAssertEqual(run.beginTerminal { 2 }, 2)
        XCTAssertFalse(run.markCallbackDelivered())
        XCTAssertFalse(run.isStopping)
        XCTAssertEqual(run.begin { 3 }, 3)
        XCTAssertFalse(run.isCurrent(1))
        XCTAssertFalse(run.completeAuthorization(generation: 1))
        XCTAssertTrue(run.isCurrent(3))
    }

    func testRecoveryConfigurationFailureEndsOldRunAndCanRetry() throws {
        enum Failure: Error { case configuration }
        let ingress = CameraFrameIngressGate(maximumInFlightFrameCount: 1)
        var run = CameraRunLifecycle()
        let original = try XCTUnwrap(run.begin { ingress.reset() })
        var failures = 0
        var restarts = 0
        func recover() {
            CameraSessionRecovery.run(isCurrent: { run.isCurrent(original) }, configure: {
                throw Failure.configuration
            }, restart: {
                restarts += 1
                return true
            }, ready: { XCTFail("失败配置不能交付就绪") }, failed: { error in
                XCTAssertTrue(error is Failure)
                failures += 1
                XCTAssertNotNil(run.beginTerminal { ingress.rejectFurtherFrames() })
                _ = run.markCallbackDelivered()
            })
        }
        recover()
        recover()
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(restarts, 0)
        XCTAssertFalse(ingress.isCurrentGeneration(original))
        XCTAssertNotNil(run.begin { ingress.reset() })
    }

    func testStopDuringRecoveryCannotRestartOrFailNewRun() throws {
        var run = CameraRunLifecycle()
        _ = run.begin { 1 }
        CameraSessionRecovery.run(isCurrent: { run.isCurrent(1) }, configure: {
            _ = run.beginTerminal { 2 }
            _ = run.markCallbackDelivered()
            _ = run.begin { 3 }
        }, restart: {
            XCTFail("旧恢复不能启动新会话")
            return true
        },
            ready: { XCTFail("旧恢复不能交付就绪") }, failed: { _ in XCTFail("旧错误不能关闭新会话") })
        XCTAssertTrue(run.isCurrent(3))
    }

    func testSuccessfulRecoveryPublishesReadyAndRestartFailurePropagates() {
        enum Failure: Error { case restart }
        var ready = 0
        var failures = 0
        CameraSessionRecovery.run(isCurrent: { true }, configure: {}, restart: { true },
            ready: { ready += 1 }, failed: { _ in failures += 1 })
        CameraSessionRecovery.run(isCurrent: { true }, configure: {}, restart: { throw Failure.restart },
            ready: { ready += 1 }, failed: { _ in failures += 1 })
        XCTAssertEqual(ready, 1)
        XCTAssertEqual(failures, 1)
    }

    func testPressureObservationDoesNotOverrideInterruptionPauseOrFailure() {
        for action: CameraLifecycleAction in [.wasInterrupted, .pauseRequested, .didStopRunning, .runtimeError(isRecoverable: false, description: "failure")] {
            var lifecycle = CameraSessionLifecycle(position: .back)
            lifecycle.handle(.didStartRunning)
            lifecycle.handle(action)
            let expected = lifecycle.state
            XCTAssertEqual(lifecycle.handle(.systemPressureChanged("serious")), .systemPressureChanged("serious"))
            XCTAssertEqual(lifecycle.state, expected)
        }
        var interrupted = CameraSessionLifecycle(position: .back)
        interrupted.handle(.didStartRunning)
        interrupted.handle(.wasInterrupted)
        interrupted.handle(.systemPressureChanged("serious"))
        XCTAssertEqual(interrupted.handle(.interruptionEnded), .interruptionEnded)
        XCTAssertEqual(interrupted.state, .running)
    }

    func testSuccessfulPositionRollbackLeavesSourceRunningAndFatalStateStaysFatal() {
        var lifecycle = CameraSessionLifecycle(position: .back)
        lifecycle.handle(.didStartRunning)
        lifecycle.handle(.positionSwitchRequested(.front))
        lifecycle.handle(.runtimeError(isRecoverable: true, description: "switch rolled back"))
        lifecycle.handle(.positionChanged(.back))
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.position, .back)
        lifecycle.handle(.runtimeError(isRecoverable: false, description: "fatal"))
        lifecycle.handle(.positionChanged(.back))
        XCTAssertEqual(lifecycle.state, .error)
    }

}
