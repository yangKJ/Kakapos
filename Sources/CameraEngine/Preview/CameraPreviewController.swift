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
    public struct Summary {
        public let mode: Mode
        public let sourceSummaryText: String
        public let pipelineSummaryText: String?
        public let previewState: PreviewSink.State?
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastErrorDescription: String?

        public var summaryText: String {
            var text = "mode \(mode) · source \(sourceSummaryText)"
            if let previewState {
                text += " · preview \(previewState)"
            }
            if let lastFrameIndex {
                text += " · frame \(lastFrameIndex)"
            }
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let pipelineSummaryText {
                text += " · pipeline \(pipelineSummaryText)"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }
    }

    public enum Mode: Equatable, Sendable {
        case raw
        case processed
    }

    public let source: CameraSource
    public let mode: Mode
    public let previewLayer: AVCaptureVideoPreviewLayer
    public let previewSink: PreviewSink?
    public let previewPipeline: PreviewPipeline?

    public var state: PreviewSink.State? {
        previewSink?.state
    }

    public var summary: Summary {
        Summary(
            mode: mode,
            sourceSummaryText: source.summaryText,
            pipelineSummaryText: previewPipeline?.summaryText,
            previewState: previewSink?.state,
            lastFrameIndex: previewSink?.snapshot.lastFrameIndex,
            lastPresentationTime: previewSink?.snapshot.lastPresentationTime,
            lastErrorDescription: previewPipeline?.lastErrorDescription
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

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
