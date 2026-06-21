//
//  RecordingPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class RecordingPipeline {
    public struct Summary {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineState: MediaPipeline.State
        public let recorderState: RecorderSink.State
        public let clipCount: Int
        public let totalDuration: CMTime
        public let currentClipDuration: CMTime
        public let hasRecordedClip: Bool
        public let lastErrorDescription: String?

        public var summaryText: String {
            let totalText = String(format: "%.2fs", totalDuration.seconds)
            let currentText = String(format: "%.2fs", currentClipDuration.seconds)
            var text = "source \(sourceTypeName) · processors \(processorCount) · pipeline \(pipelineState) · recorder \(recorderState) · clips \(clipCount) · total \(totalText) · clip \(currentText) · recorded \(hasRecordedClip ? "yes" : "no")"
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }
    }

    public let source: MediaSource
    public let recorderSink: RecorderSink
    public let pipeline: MediaPipeline

    public var processors: [FrameProcessor] {
        get { pipeline.processors }
        set { pipeline.processors = newValue }
    }

    public var state: MediaPipeline.State {
        pipeline.state
    }

    public var summary: Summary {
        let snapshot = recorderSink.snapshot
        return Summary(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            recorderState: recorderSink.state,
            clipCount: snapshot.clipCount,
            totalDuration: snapshot.totalDuration,
            currentClipDuration: snapshot.currentClipDuration,
            hasRecordedClip: snapshot.hasRecordedClip,
            lastErrorDescription: pipeline.lastErrorDescription
        )
    }

    public var lastErrorDescription: String? {
        pipeline.lastErrorDescription
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(
        source: MediaSource,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws {
        self.source = source
        self.recorderSink = try RecorderSink(outputURL: outputURL, fileType: fileType)
        self.pipeline = MediaPipeline(source: source, processors: processors, sinks: [recorderSink])
    }

    public func start() {
        pipeline.start()
    }

    public func pause() {
        pipeline.pause()
    }

    public func resume() {
        pipeline.resume()
    }

    public func stop() {
        pipeline.stop()
    }

    public func cancel() {
        pipeline.cancel()
    }
}

#if canImport(UIKit) && !os(watchOS)
public extension RecordingPipeline {
    convenience init(
        configuration: CameraSourceConfiguration = CameraSourceConfiguration(),
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws {
        let source = try CameraSource(configuration: configuration)
        try self.init(source: source, outputURL: outputURL, fileType: fileType, processors: processors)
    }

    var cameraSource: CameraSource? {
        source as? CameraSource
    }
}
#endif
