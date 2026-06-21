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
        public let sourceSnapshot: MediaSourceSnapshot?
#if canImport(UIKit) && !os(watchOS)
        public let cameraSourceState: CameraSessionState?
        public let cameraSourcePosition: CameraPosition?
        public let cameraSourceAuthorizationStatus: CameraAuthorizationStatus?
        public let cameraSourceIsPaused: Bool?
        public let cameraSourceCaptureMode: CameraCaptureMode?
        public let cameraSourceLastFrameIndex: Int64?
        public let cameraSourceLastPresentationTime: CMTime?
        public let cameraSourceLastMediaType: String?
#endif
        public let clipCount: Int
        public let totalDuration: CMTime
        public let currentClipDuration: CMTime
        public let hasRecordedClip: Bool
        public let currentClipHasStarted: Bool
        public let currentClipHasVideo: Bool
        public let currentClipHasAudio: Bool
        public let recordedVideoSegmentCount: Int
        public let recordedAudioSegmentCount: Int
        public let lastErrorDescription: String?

        public var summaryText: String {
            let totalText = String(format: "%.2fs", totalDuration.seconds)
            let currentText = String(format: "%.2fs", currentClipDuration.seconds)
            var text = "source \(sourceTypeName) · processors \(processorCount) · pipeline \(pipelineState) · recorder \(recorderState) · clips \(clipCount) · total \(totalText) · clip \(currentText) · recorded \(hasRecordedClip ? "yes" : "no") · started \(currentClipHasStarted ? "yes" : "no") · video \(currentClipHasVideo ? "yes" : "no") · audio \(currentClipHasAudio ? "yes" : "no") · segments v\(recordedVideoSegmentCount)/a\(recordedAudioSegmentCount)"
            if let sourceSnapshot {
                text += " · sourceSnapshot \(sourceSnapshot.summaryText)"
            }
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
#if canImport(UIKit) && !os(watchOS)
        let cameraSummary = cameraSource?.summary
        return Summary(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            recorderState: recorderSink.state,
            sourceSnapshot: pipeline.summary.sourceSnapshot,
            cameraSourceState: cameraSummary?.state,
            cameraSourcePosition: cameraSummary?.position,
            cameraSourceAuthorizationStatus: cameraSummary?.authorizationStatus,
            cameraSourceIsPaused: cameraSummary?.isPaused,
            cameraSourceCaptureMode: cameraSummary?.captureMode,
            cameraSourceLastFrameIndex: cameraSummary?.lastFrameIndex,
            cameraSourceLastPresentationTime: cameraSummary?.lastPresentationTime,
            cameraSourceLastMediaType: cameraSummary?.lastMediaType,
            clipCount: snapshot.clipCount,
            totalDuration: snapshot.totalDuration,
            currentClipDuration: snapshot.currentClipDuration,
            hasRecordedClip: snapshot.hasRecordedClip,
            currentClipHasStarted: snapshot.currentClipHasStarted,
            currentClipHasVideo: snapshot.currentClipHasVideo,
            currentClipHasAudio: snapshot.currentClipHasAudio,
            recordedVideoSegmentCount: snapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: snapshot.recordedAudioSegmentCount,
            lastErrorDescription: pipeline.lastErrorDescription
        )
#else
        return Summary(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            recorderState: recorderSink.state,
            sourceSnapshot: pipeline.summary.sourceSnapshot,
            clipCount: snapshot.clipCount,
            totalDuration: snapshot.totalDuration,
            currentClipDuration: snapshot.currentClipDuration,
            hasRecordedClip: snapshot.hasRecordedClip,
            currentClipHasStarted: snapshot.currentClipHasStarted,
            currentClipHasVideo: snapshot.currentClipHasVideo,
            currentClipHasAudio: snapshot.currentClipHasAudio,
            recordedVideoSegmentCount: snapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: snapshot.recordedAudioSegmentCount,
            lastErrorDescription: pipeline.lastErrorDescription
        )
#endif
    }

    public var lastErrorDescription: String? {
        pipeline.lastErrorDescription
    }

    public var sourceSnapshot: MediaSourceSnapshot? {
        summary.sourceSnapshot
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
