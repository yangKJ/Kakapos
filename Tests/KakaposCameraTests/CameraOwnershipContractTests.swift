// 作者：Condy
import AVFoundation
import XCTest
@testable import KakaposCamera
import KakaposVideo

final class CameraOwnershipContractTests: XCTestCase {
    func testConcurrentBranchesShareOneNativeStartAndLastStop() {
        var running = false; var starts = 0; var stops = 0
        let owner = CameraSessionOwner(isRunning: { running }, start: { running = true; starts += 1 }, stop: { running = false; stops += 1 })
        let tokens = (0..<16).map { _ in UUID() }
        DispatchQueue.concurrentPerform(iterations: tokens.count) { owner.start(tokens[$0]) }
        XCTAssertEqual(owner.sync { starts }, 1)
        DispatchQueue.concurrentPerform(iterations: tokens.count - 1) { owner.stop(tokens[$0]) }
        XCTAssertEqual(owner.sync { stops }, 0)
        owner.stop(tokens.last!); owner.stop(tokens.last!)
        XCTAssertEqual(owner.sync { stops }, 1)
    }
    func testBatchNeverStartsInsideConfigurationAndSupportsReentry() {
        var running = false; var depth = 0; var startedAtDepth: [Int] = []
        let owner = CameraSessionOwner(isRunning: { running }, start: { startedAtDepth.append(depth); running = true }, stop: { running = false })
        owner.batch {
            depth += 1
            owner.start(UUID())
            owner.sync { owner.start(UUID()) }
            XCTAssertTrue(startedAtDepth.isEmpty)
            depth -= 1
        }
        XCTAssertEqual(startedAtDepth, [0])
    }
    func testBorrowedRunningSessionIsNotStoppedByBranchRelease() {
        var stops = 0
        let owner = CameraSessionOwner(isRunning: { true }, start: { XCTFail("不应重新启动宿主会话") }, stop: { stops += 1 })
        let token = UUID(); owner.start(token); owner.stop(token)
        XCTAssertEqual(stops, 0)
    }
    func testNativeOwnerRegistryUsesSessionIdentityWithoutRetainingOwners() {
        let session = AVCaptureSession()
        var a: CameraSessionOwner? = .shared(for: session)
        var b: CameraSessionOwner? = .shared(for: session)
        XCTAssertTrue(a === b)
        weak var weakOwner = a
        a = nil; b = nil
        XCTAssertNil(weakOwner)
    }
    func testAudioLeaseIdempotenceAndLastRelease() throws {
        var activations: [Bool] = []; var stops = 0; var restores = 0
        let leases = CameraAudioLeaseCoordinator(activate: { activations.append($0) }, deactivate: { stops += 1 }, restore: { restores += 1 })
        let a = UUID(); let b = UUID()
        XCTAssertTrue(try leases.acquire(a, mixes: true)); XCTAssertFalse(try leases.acquire(a, mixes: true))
        XCTAssertTrue(try leases.acquire(b, mixes: true)); XCTAssertEqual(activations, [true])
        XCTAssertTrue(try leases.release(a)); XCTAssertEqual(stops, 0)
        XCTAssertFalse(try leases.release(a)); XCTAssertTrue(try leases.release(b))
        XCTAssertEqual(stops, 1); XCTAssertEqual(restores, 1)
    }
    func testAudioPolicyConflictAndActivationFailurePreserveExistingOwner() throws {
        enum Failure: Error { case unavailable }
        var fails = true; var calls = 0
        let leases = CameraAudioLeaseCoordinator(activate: { _ in calls += 1; if fails { throw Failure.unavailable } }, deactivate: {})
        let a = UUID(); let b = UUID()
        XCTAssertThrowsError(try leases.acquire(a, mixes: false)); XCTAssertFalse(leases.contains(a))
        fails = false; try leases.acquire(a, mixes: false)
        XCTAssertThrowsError(try leases.acquire(b, mixes: true)); XCTAssertTrue(leases.contains(a)); XCTAssertFalse(leases.contains(b))
        XCTAssertEqual(calls, 2)
    }
    func testAudioInterruptionAndResetResumeOnceForAllLeases() throws {
        var activations = 0; var deactivations = 0
        let leases = CameraAudioLeaseCoordinator(activate: { _ in activations += 1 }, deactivate: { deactivations += 1 })
        let a = UUID(); let b = UUID(); try leases.acquire(a, mixes: false); try leases.acquire(b, mixes: false)
        leases.interrupted(); try leases.resumeIfNeeded(); try leases.resumeIfNeeded()
        XCTAssertEqual(activations, 2)
        leases.interrupted(); try leases.release(a); try leases.release(b); try leases.resumeIfNeeded()
        XCTAssertEqual(activations, 2); XCTAssertEqual(deactivations, 0)
    }
    func testAudioReleaseFailureCanRetryAndRestoreFailureStillReleasesLease() throws {
        enum Failure: Error { case unavailable }
        var stopFails = true; var restoreFails = false
        let leases = CameraAudioLeaseCoordinator(activate: { _ in }, deactivate: { if stopFails { throw Failure.unavailable } }, restore: { if restoreFails { throw Failure.unavailable } })
        let token = UUID(); try leases.acquire(token, mixes: false)
        XCTAssertThrowsError(try leases.release(token)); XCTAssertTrue(leases.contains(token))
        stopFails = false; restoreFails = true
        XCTAssertThrowsError(try leases.release(token)); XCTAssertFalse(leases.contains(token))
    }
    func testAudioOwnershipPolicyDoesNotManagePhotoOrSilentPreview() {
        for mode in [CameraCaptureMode.photo, .videoWithoutAudio, .video] {
            for policy in [CameraAudioSessionOwnership.automatic, .hostManaged] {
                let config = CameraAudioConfiguration(sessionOwnership: policy)
                XCTAssertEqual(config.managesSession(for: mode), mode == .video && policy == .automatic)
            }
        }
    }
    func testAdvancedEventsPublishExactConcurrentCountAndSupportReentrantSnapshots() {
        let output = CameraAdvancedOutput(); let lock = NSLock(); var callbacks = 0
        let token = output.addEventObserver { _ in
            _ = output.snapshot
            lock.lock(); callbacks += 1; lock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<10_000 { output.emitPortraitEffectsMatte(.init(deliveredInPhoto: false)) }
        }
        XCTAssertEqual(output.snapshot.eventCount, 80_000); XCTAssertEqual(callbacks, 80_000)
        XCTAssertEqual(output.snapshot.latestEvent?.kind, .portraitEffectsMatte)
        output.removeEventObserver(token); output.reset()
        XCTAssertEqual(output.snapshot.eventCount, 0); XCTAssertNil(output.snapshot.latestEvent)
    }
    func testStrictFormatAndColorAreResolvedTogetherWithoutUsingEncodingCanvas() throws {
        let formats: [CameraVideoFormatCandidate] = [
            .init(width: 1280, height: 720, frameRateRanges: [], colorPolicies: [.standardBT709]),
            .init(width: 1920, height: 1080, frameRateRanges: [], colorPolicies: [.hdrHLG]),
            .init(width: 1280, height: 720, frameRateRanges: [], colorPolicies: [.hdrHLG])
        ]
        for color in [VideoExportColorPolicy.standardBT709, .hdrHLG] {
            let config = CameraVideoConfiguration(dimensions: CGSize(width: 1920, height: 1080), codec: .hevc, colorPolicy: color,
                formatSelectionPolicy: .requireRequested, captureDimensions: CGSize(width: 1280, height: 720))
            let index = try XCTUnwrap(config.preferredFormatIndex(in: formats, currentIndex: 1))
            XCTAssertEqual(index, color == .hdrHLG ? 2 : 0)
            XCTAssertThrowsError(try config.preferredFormatIndex(in: [formats[1]]))
        }
    }
    func testExplicitColorPreservesLegacyDimensionsOnlyWithoutCaptureRequest() throws {
        let formats = [CameraVideoFormatCandidate(width: 1280, height: 720, frameRateRanges: []), .init(width: 1920, height: 1080, frameRateRanges: [])]
        var config = CameraVideoConfiguration(dimensions: CGSize(width: 1920, height: 1080), colorPolicy: .standardBT709)
        XCTAssertEqual(try config.preferredFormatIndex(in: formats, currentIndex: 0), 1)
        config.captureDimensions = CGSize(width: 1280, height: 720)
        XCTAssertEqual(try config.preferredFormatIndex(in: formats, currentIndex: 1), 0)
    }
    #if os(macOS)
    func testNativeGraphRollbackRestoresRemovedOutputsAndAllowsRetry() throws {
        enum Failure: Error { case injected }
        for failureStage in 0..<3 {
            let session = AVCaptureSession(); let original = AVCaptureVideoDataOutput()
            XCTAssertTrue(session.canAddOutput(original)); session.addOutput(original)
            let replacement = AVCaptureVideoDataOutput()
            XCTAssertThrowsError(try CameraCaptureTransaction(session: session).run {
                session.removeOutput(original)
                if failureStage == 0 { throw Failure.injected }
                XCTAssertTrue(session.canAddOutput(replacement)); session.addOutput(replacement)
                if failureStage == 1 { throw Failure.injected }
                if session.canSetSessionPreset(.low) { session.sessionPreset = .low }
                throw Failure.injected
            })
            XCTAssertEqual(session.outputs.count, 1); XCTAssertTrue(session.outputs.first === original)
            try CameraCaptureTransaction(session: session).run {
                session.removeOutput(original); session.addOutput(replacement)
            }
            XCTAssertEqual(session.outputs.count, 1); XCTAssertTrue(session.outputs.first === replacement)
        }
    }
    #endif
}
