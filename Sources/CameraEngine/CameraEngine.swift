//
//  CameraEngine.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public final class CameraEngine {
    public let source: CameraSource
    public let deviceController: CameraDeviceController
    public let advancedOutput: CameraAdvancedOutput
    public private(set) var previewController: CameraPreviewController?
    public private(set) var recordingController: CameraRecordingController?

    public init(configuration: CameraCaptureConfiguration = .init()) throws {
        let source = try CameraSource(configuration: configuration)
        self.source = source
        self.deviceController = source.deviceController
        self.advancedOutput = source.advancedOutput
    }

    public func makePreviewController(
        mode: CameraPreviewController.Mode = .raw,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: PreviewSink.Handler? = nil
    ) -> CameraPreviewController {
        let controller = CameraPreviewController(
            source: source,
            mode: mode,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
        previewController = controller
        return controller
    }

    public func makeRecordingController(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws -> CameraRecordingController {
        let controller = try CameraRecordingController(
            source: source,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
        recordingController = controller
        return controller
    }

    public func start() {
        source.start()
        previewController?.start()
    }

    public func pause() {
        source.pause()
        previewController?.pause()
        recordingController?.pause()
    }

    public func resume() {
        source.resume()
        previewController?.resume()
        recordingController?.resume()
    }

    public func stop() {
        source.stop()
        previewController?.stop()
        recordingController?.stop()
    }

    public func cancel() {
        source.cancel()
        previewController?.stop()
        recordingController?.cancel()
    }

    @discardableResult
    public func switchCameraPosition() -> Bool {
        source.switchCameraPosition()
    }

    public func capturePhoto() {
        source.capturePhoto()
    }
}
#endif
