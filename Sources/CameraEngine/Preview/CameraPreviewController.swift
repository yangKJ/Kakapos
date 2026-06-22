//
//  CameraPreviewController.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public final class CameraPreviewController {
    public enum Mode: Equatable, Sendable {
        case raw
        case processed
    }

    public let source: CameraSource
    public let mode: Mode
    public let previewLayer: AVCaptureVideoPreviewLayer
    public let previewSink: PreviewSink?
    public let previewPipeline: PreviewPipeline?

    public init(
        source: CameraSource,
        mode: Mode = .raw,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: PreviewSink.Handler? = nil
    ) {
        self.source = source
        self.mode = mode
        self.previewLayer = source.previewLayer
        switch mode {
        case .raw:
            self.previewSink = nil
            self.previewPipeline = nil
        case .processed:
            let resolvedHandler = handler ?? { _, _ in }
            let pipeline = PreviewPipeline(
                source: source,
                processors: processors,
                callbackQueue: callbackQueue,
                handler: resolvedHandler
            )
            self.previewSink = pipeline.previewSink
            self.previewPipeline = pipeline
        }
    }

    public func start() {
        previewPipeline?.start()
    }

    public func pause() {
        previewPipeline?.pause()
    }

    public func resume() {
        previewPipeline?.resume()
    }

    public func stop() {
        previewPipeline?.stop()
    }
}
#endif
