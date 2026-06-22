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
