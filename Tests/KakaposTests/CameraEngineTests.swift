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

    func testCameraSnapshotsAndAdvancedEventsExposeReadableSummaries() {
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

        let device = CameraDeviceSnapshot(
            position: .back,
            zoomFactor: 2,
            lensPosition: 0.4,
            exposureBias: 1,
            torchActive: true,
            flashAvailable: true,
            torchAvailable: true,
            focusPoint: CGPoint(x: 0.2, y: 0.8),
            exposurePoint: CGPoint(x: 0.3, y: 0.7),
            activeFormatDescription: "format-desc",
            activeFrameRateRange: .init(minimumFramesPerSecond: 24, maximumFramesPerSecond: 60)
        )
        XCTAssertTrue(device.summaryText.contains("zoom 2.00x"))
        XCTAssertTrue(device.summaryText.contains("torch on"))
        XCTAssertTrue(device.summaryText.contains("fps 24.0-60.0"))
        XCTAssertTrue(device.summaryText.contains("format format-desc"))

        let advancedOutput = CameraAdvancedOutput()
        var receivedKinds: [CameraAdvancedEvent.Kind] = []
        advancedOutput.eventHandler = { receivedKinds.append($0.kind) }
        advancedOutput.emitMetadataObjects(.init(objects: [], timestamp: CMTime(seconds: 3, preferredTimescale: 600)))
        advancedOutput.emitDepthData(.init(timestamp: CMTime(seconds: 5, preferredTimescale: 600)))

        XCTAssertEqual(receivedKinds, [.metadataObjects, .depthData])
        XCTAssertEqual(
            CameraAdvancedEvent.depthData(.init(timestamp: CMTime(seconds: 5, preferredTimescale: 600))).summaryText,
            "depthData timestamp 5.00s"
        )
    }

    func testCameraRecordingControllerStopsAndFinishesGenericSource() throws {
        let frame = MediaFrame(
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
            case .clipCountChanged(let count):
                events.append("clips:\(count)")
            case .durationChanged(let duration):
                events.append(String(format: "duration:%.2f", duration.seconds))
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
