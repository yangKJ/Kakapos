import XCTest
import AVFoundation
@testable import Kakapos

final class CameraEngineTests: XCTestCase {

    func testCameraPositionAndVideoStabilizationModeAreCodable() throws {
        let payload = [
            "position": CameraPosition.front.rawValue,
            "stabilization": CameraVideoStabilizationMode.auto.rawValue
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]

        XCTAssertEqual(CameraPosition(rawValue: decoded?["position"] ?? ""), .front)
        XCTAssertEqual(CameraVideoStabilizationMode(rawValue: decoded?["stabilization"] ?? ""), .auto)
    }

    func testCameraCaptureConfigurationExposesAudioDeviceAndAdvancedSettings() {
        let configuration = CameraCaptureConfiguration(
            captureMode: .video,
            preferredPosition: .front,
            preferredDeviceTypes: [.trueDepth, .wideAngle],
            mirroringMode: .on,
            video: CameraVideoConfiguration(
                sessionPreset: .high,
                preferredFrameRateRange: CameraFrameRateRange(minimumFramesPerSecond: 24, maximumFramesPerSecond: 60)
            ),
            audio: CameraAudioConfiguration(sampleRate: 48_000, channelCount: 2, bitRate: 192_000, prefersIndependentSession: true),
            photo: CameraPhotoConfiguration(deliversDepthData: true, deliversPortraitEffectsMatte: true),
            advanced: CameraAdvancedCaptureSettings(
                metadataObjectTypes: [.qr, .face],
                enablesDepthData: true,
                enablesPortraitEffectsMatte: true,
                enablesARFrameSource: true,
                enablesMultiCam: true
            )
        )

        XCTAssertEqual(configuration.device.preferredPosition, .front)
        XCTAssertEqual(configuration.device.preferredDeviceTypes, [.trueDepth, .wideAngle])
        XCTAssertEqual(configuration.device.mirroringMode, .on)
        XCTAssertEqual(configuration.audio.sampleRate, 48_000)
        XCTAssertEqual(configuration.audio.channelCount, 2)
        XCTAssertTrue(configuration.audio.prefersIndependentSession)
        XCTAssertEqual(configuration.advanced.metadataObjectTypes, [.qr, .face])
        XCTAssertTrue(configuration.advanced.enablesDepthData)
        XCTAssertTrue(configuration.advanced.enablesPortraitEffectsMatte)
        XCTAssertTrue(configuration.advanced.enablesARFrameSource)
        XCTAssertTrue(configuration.advanced.enablesMultiCam)
    }

    func testCameraSnapshotsAndAdvancedEventsExposeReadableSummaries() throws {
        let capability = CameraCapabilitySnapshot(
            supportsAudioCapture: true,
            supportsPhotoCapture: true,
            supportsMetadataObjects: .supported,
            supportsDepthData: .unsupported,
            supportsPortraitEffectsMatte: .supported,
            supportsARFrameSource: .unknown,
            supportsMultiCam: .supported,
            supportsTorch: .supported,
            supportsFlash: .unsupported,
            currentPosition: .front,
            isMirrored: true,
            activeVideoDimensions: CGSize(width: 1920, height: 1080)
        )
        XCTAssertTrue(capability.summaryText.contains("audio yes"))
        XCTAssertTrue(capability.summaryText.contains("metadata supported"))
        XCTAssertTrue(capability.summaryText.contains("position front"))
        XCTAssertTrue(capability.summaryText.contains("size 1920x1080"))
        XCTAssertEqual(capability.status(for: .metadataObjects), .supported)
        XCTAssertEqual(capability.status(for: .depth), .unsupported)
        XCTAssertEqual(capability.gateStatuses[.multicam], .supported)

        let device = CameraDeviceSnapshot(
            position: .back,
            zoomFactor: 2,
            lensPosition: 0.4,
            exposureBias: 1,
            iso: 120,
            exposureDuration: CMTime(value: 1, timescale: 120),
            torchActive: true,
            flashAvailable: true,
            torchAvailable: true,
            focusPoint: CGPoint(x: 0.2, y: 0.8),
            exposurePoint: CGPoint(x: 0.3, y: 0.7),
            focusMode: .locked,
            exposureMode: .custom,
            whiteBalanceMode: .locked,
            activeDeviceType: "wideAngle",
            subjectAreaMonitoringEnabled: true,
            isAdjustingFocus: false,
            isAdjustingExposure: false,
            whiteBalanceGains: [1.1, 1.2, 1.3],
            activeFormatDescription: "format-desc",
            activeFrameRateRange: .init(minimumFramesPerSecond: 24, maximumFramesPerSecond: 60)
        )
        XCTAssertTrue(device.summaryText.contains("zoom 2.00x"))
        XCTAssertTrue(device.summaryText.contains("torch on"))
        XCTAssertTrue(device.summaryText.contains("iso 120.0"))
        XCTAssertTrue(device.summaryText.contains("whiteBalance locked"))
        XCTAssertTrue(device.summaryText.contains("fps 24.0-60.0"))
        XCTAssertTrue(device.summaryText.contains("format format-desc"))

        let advancedOutput = CameraAdvancedOutput()
        var receivedKinds: [CameraAdvancedEvent.Kind] = []
        var observerKinds: [CameraAdvancedEvent.Kind] = []
        advancedOutput.eventHandler = { receivedKinds.append($0.kind) }
        _ = advancedOutput.addEventObserver { observerKinds.append($0.kind) }
        advancedOutput.emitMetadataObjects(.init(objects: [], timestamp: CMTime(seconds: 3, preferredTimescale: 600)))
        advancedOutput.emitDepthData(.init(timestamp: CMTime(seconds: 5, preferredTimescale: 600)))
        let pixelBuffer = try makeCameraTestPixelBuffer(width: 8, height: 8)
        let frame = PixelBufferFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(
                presentationTime: CMTime(seconds: 6, preferredTimescale: 600),
                sourceTime: CMTime(seconds: 6, preferredTimescale: 600),
                frameIndex: 0
            )
        )
        advancedOutput.emit(.arFrame(.init(
            frame: frame,
            timestamp: CMTime(seconds: 6, preferredTimescale: 600),
            includesAudio: true
        )))

        XCTAssertEqual(receivedKinds, [.metadataObjects, .depthData, .arFrame])
        XCTAssertEqual(observerKinds, [.metadataObjects, .depthData, .arFrame])
        XCTAssertEqual(advancedOutput.eventCount, 3)
        XCTAssertEqual(advancedOutput.latestEventKind, .arFrame)
        XCTAssertEqual(advancedOutput.latestEventSummaryText, "arFrame presentation 6.00s · audio yes")
        advancedOutput.reset()
        XCTAssertEqual(advancedOutput.eventCount, 0)
        XCTAssertNil(advancedOutput.latestEventKind)
        XCTAssertEqual(
            CameraAdvancedEvent.depthData(.init(timestamp: CMTime(seconds: 5, preferredTimescale: 600))).summaryText,
            "depthData synchronized no · timestamp 5.00s"
        )
    }

    func testCameraRecordingControllerStopsAndFinishesGenericSource() throws {
        let frame = PixelBufferFrame(
            pixelBuffer: try makeCameraTestPixelBuffer(width: 16, height: 16),
            metadata: FrameMetadata(
                presentationTime: CMTime(seconds: 0, preferredTimescale: 600),
                duration: CMTime(value: 1, timescale: 30),
                sourceTime: CMTime(seconds: 0, preferredTimescale: 600),
                frameIndex: 0
            )
        )
        let source = CameraTestSource(frames: [frame])
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let controller = try CameraRecordingController(
            source: source,
            outputURL: outputURL
        )

        var states: [RecorderSink.State] = []
        var events: [String] = []
        controller.stateChangedHandler = { states.append($0) }
        controller.eventHandler = { event in
            switch event {
            case .willStart:
                events.append("willStart")
            case .didStart:
                events.append("start")
            case .didPause:
                events.append("pause")
            case .didResume:
                events.append("resume")
            case .didFinish:
                events.append("finish")
            case .didCancel:
                events.append("cancel")
            case .didFail(let description):
                events.append("fail:\(description)")
            case .clipCompleted(let clip):
                events.append("segment:\(clip.index)")
            case .clipCountChanged(let count):
                events.append("clips:\(count)")
            case .durationChanged(let duration):
                events.append(String(format: "duration:%.2f", duration.seconds))
            case .droppedFrame(let metadata):
                events.append("drop:\(metadata.frameIndex ?? -1)")
            }
        }

        controller.start()

        let expectation = expectation(description: "stop recording")
        var finishedClip: RecordedClip?
        controller.stopRecording { result in
            if case .success(let clip) = result {
                finishedClip = clip
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(controller.state, .finished)
        XCTAssertTrue(controller.summaryText.contains("recorder finished"))
        XCTAssertTrue(states.contains(.recording))
        XCTAssertTrue(states.contains(.finished))
        XCTAssertTrue(events.contains("start"))
        XCTAssertTrue(events.contains("finish"))
        XCTAssertEqual(finishedClip?.outputURL, outputURL)
        XCTAssertEqual(controller.recordedClip?.outputURL, outputURL)
        XCTAssertNotNil(controller.makeRecordedClipAssetSource())
        XCTAssertNotNil(controller.makeRecordedClipTimelinePipeline())
        XCTAssertNotNil(controller.makeRecordedClipExportJob(outputURL: outputURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")))
        XCTAssertNotNil(controller.makeRecordedClipExportTask(outputURL: outputURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")))
#if canImport(UIKit) || os(macOS)
        XCTAssertNotNil(controller.makeRecordedClipPlayerFrameSource())
        XCTAssertNotNil(controller.makeRecordedClipPreviewPipeline { _, _ in })
#endif
    }

    #if canImport(UIKit) && !os(watchOS)
    func testCameraDeviceControllerReturnsUnavailableSnapshotAndStoresPreferredFlashMode() {
        let controller = CameraDeviceController(
            deviceProvider: { nil },
            positionProvider: { .front }
        )

        let initialSnapshot = controller.snapshot
        XCTAssertEqual(initialSnapshot.position, .front)
        XCTAssertEqual(initialSnapshot.zoomFactor, 1)
        XCTAssertFalse(initialSnapshot.flashAvailable)
        XCTAssertFalse(initialSnapshot.torchAvailable)

        let updatedSnapshot = controller.setPreferredFlashMode(.on)
        XCTAssertEqual(controller.preferredFlashMode, .on)
        XCTAssertEqual(updatedSnapshot.position, .front)
    }

    func testCameraSourceConfigurationWithDevicePersistsControlPreferences() {
        let configuration = CameraSourceConfiguration.cameraDefaults()
            .withDevice {
                var device = $0
                device.focusMode = .locked
                device.exposureMode = .custom
                device.whiteBalanceMode = .locked
                device.initialZoomFactor = 2
                device.enablesSmoothAutoFocus = false
                device.subjectAreaMonitoringEnabled = false
                return device
            }

        XCTAssertEqual(configuration.device.focusMode, .locked)
        XCTAssertEqual(configuration.device.exposureMode, .custom)
        XCTAssertEqual(configuration.device.whiteBalanceMode, .locked)
        XCTAssertEqual(configuration.device.initialZoomFactor, 2)
        XCTAssertFalse(configuration.device.enablesSmoothAutoFocus)
        XCTAssertFalse(configuration.device.subjectAreaMonitoringEnabled)
    }
#endif

#if canImport(UIKit) && !os(watchOS)
    func testCameraEngineBuildsPreviewAndRecordingControllers() throws {
        let engine = try CameraEngine(
            configuration: CameraCaptureConfiguration(captureMode: .videoWithoutAudio)
        )

        XCTAssertTrue(engine.previewLayer === engine.source.previewLayer)
        XCTAssertEqual(engine.snapshot.captureMode, .videoWithoutAudio)
        XCTAssertTrue(engine.summaryText.contains("mode videoWithoutAudio"))

        let previewController = engine.makePreviewController(mode: .processed, processors: [])
        XCTAssertEqual(previewController.mode, .processed)
        XCTAssertNotNil(previewController.previewPipeline)
        XCTAssertNotNil(previewController.previewSink)
        XCTAssertTrue(previewController.previewLayer === engine.source.previewLayer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let recordingController = try engine.makeRecordingController(outputURL: outputURL)
        XCTAssertTrue(recordingController.source === engine.source)
        XCTAssertTrue(recordingController.pipeline.cameraSource === engine.source)
        XCTAssertEqual(engine.deviceSnapshot.position, engine.source.currentPosition)
        XCTAssertTrue(engine.capabilitySummaryText.contains("position"))
        XCTAssertNotNil(engine.previewSummaryText)
        XCTAssertNotNil(engine.recordingSummaryText)
    }

    func testCameraPreviewControllerSummarizesModeAndSourceState() throws {
        let engine = try CameraEngine(
            configuration: CameraCaptureConfiguration(captureMode: .videoWithoutAudio)
        )
        let previewController = engine.makePreviewController(mode: .processed, processors: [])

        XCTAssertEqual(previewController.state, .idle)
        XCTAssertTrue(previewController.summaryText.contains("mode processed"))
        XCTAssertTrue(previewController.summaryText.contains("state idle"))
        XCTAssertTrue(previewController.summaryText.contains("source state"))
    }

    func testCameraEngineStopRecordingFailsWithoutRecordingController() throws {
        let engine = try CameraEngine(
            configuration: CameraCaptureConfiguration(captureMode: .videoWithoutAudio)
        )
        let expectation = expectation(description: "missing recording controller")
        var receivedError: Error?

        engine.stopRecording { result in
            if case .failure(let error) = result {
                receivedError = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedError as? CameraEngineError, .recordingControllerUnavailable)
        XCTAssertNil(engine.makeRecordedClipAssetSource())
        XCTAssertNil(engine.makeRecordedClipTimelinePipeline())
        XCTAssertNil(engine.makeRecordedClipExportJob(outputURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")))
        XCTAssertNil(engine.makeRecordedClipExportTask(outputURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")))
#if canImport(UIKit) || os(macOS)
        XCTAssertNil(engine.makeRecordedClipPlayerFrameSource())
        XCTAssertNil(engine.makeRecordedClipPreviewPipeline { _, _ in })
#endif
    }

    func testCameraEngineDiagnosticsSnapshotAggregatesCurrentState() throws {
        let engine = try CameraEngine(
            configuration: CameraCaptureConfiguration(captureMode: .videoWithoutAudio)
        )
        _ = engine.makePreviewController(mode: .processed, processors: [])

        let diagnostics = engine.diagnosticsSnapshot
        XCTAssertTrue(diagnostics.sessionSummaryText.contains("mode videoWithoutAudio"))
        XCTAssertTrue(diagnostics.deviceSummaryText.contains("position"))
        XCTAssertTrue(diagnostics.capabilitySummaryText.contains("position"))
        XCTAssertTrue(diagnostics.advancedEventSummaryText.contains("No advanced camera events yet"))
        XCTAssertEqual(diagnostics.capabilityGateStatuses[.metadataObjects], .unsupported)
    }

    func testCameraEngineDiagnosticsDoNotOverrideExternalSourceHandlers() throws {
        let engine = try CameraEngine(
            configuration: CameraCaptureConfiguration(captureMode: .videoWithoutAudio)
        )
        var receivedEvents: [CameraSessionEvent] = []

        engine.source.sessionEventHandler = { event in
            receivedEvents.append(event)
        }

        engine.source._handleLifecycleActionForTesting(.didStartRunning)

        XCTAssertEqual(receivedEvents, [.didStart])
        XCTAssertTrue(engine.diagnosticsSnapshot.recentEvents.contains("didStart"))
    }

    #if canImport(ARKit) && (os(iOS) || os(visionOS))
    @available(iOS 13.0, *)
    func testARFrameSourceSummaryTracksSupportAndAudioFlag() {
        let source = ARFrameSource(configuration: .init(includesAudio: true))
        XCTAssertTrue(source.summaryText.contains("supported yes"))
        XCTAssertTrue(source.summaryText.contains("audio yes"))
        XCTAssertTrue(source.summaryText.contains("events 0"))
        XCTAssertEqual(source.snapshot.includesAudio, true)
        XCTAssertEqual(source.snapshot.advancedEventCount, 0)
    }
    #endif

    #if canImport(UIKit) && !os(watchOS)
    @available(iOS 13.0, *)
    func testMultiCameraSnapshotIncludesUnsupportedReasonAndBranchSummaries() throws {
        let multiCamera = try MultiCameraSource()
        multiCamera.frontSource.advancedOutput.emitMetadataObjects(.init(objects: [], timestamp: CMTime(seconds: 2, preferredTimescale: 600)))
        let snapshot = multiCamera.snapshot

        XCTAssertEqual(snapshot.branches.count, 2)
        if snapshot.isSupported == false {
            XCTAssertNotNil(snapshot.unsupportedReason)
        }
        XCTAssertEqual(multiCamera.advancedOutput.eventCount, 1)
        XCTAssertEqual(multiCamera.advancedOutput.latestEventKind, .metadataObjects)
        XCTAssertTrue(multiCamera.summaryText.contains("events"))
        XCTAssertTrue(snapshot.branches[0].summaryText.contains("capability"))
    }
    #endif

    func testRecordingPipelineCameraSourceSnapshotCarriesCapabilitySnapshot() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let pipeline = try RecordingPipeline(
            configuration: .init(
                captureMode: .videoWithoutAudio,
                advanced: .init(metadataObjectTypes: [.face], enablesDepthData: true)
            ),
            outputURL: outputURL
        )

        let snapshot = try XCTUnwrap(pipeline.cameraSource?.snapshot)
        XCTAssertEqual(snapshot.capabilitySnapshot.supportsMetadataObjects, .supported)
        XCTAssertNotEqual(snapshot.capabilitySnapshot.supportsDepthData, .unknown)
    }
#endif
}

private final class CameraTestSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private let frames: [MediaFrame]

    init(frames: [MediaFrame]) {
        self.frames = frames
    }

    func start() {
        frames.forEach { delegate?.mediaSource(self, didOutput: $0) }
        delegate?.mediaSourceDidFinish(self)
    }

    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}

private func makeCameraTestPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    XCTAssertEqual(status, kCVReturnSuccess)
    return try XCTUnwrap(pixelBuffer)
}
