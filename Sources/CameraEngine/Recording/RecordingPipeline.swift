//
//  RecordingPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation

public final class RecordingPipeline {
    public struct ManifestRecorderSnapshot: Equatable, Sendable, Codable {
        public let stateDescription: String
        public let outputURL: URL
        public let recordedClipURL: URL?
        public let totalDurationSeconds: Double
        public let currentClipDurationSeconds: Double
        public let clipCount: Int
        public let currentClipHasStarted: Bool
        public let currentClipHasVideo: Bool
        public let currentClipHasAudio: Bool
        public let recordedVideoSegmentCount: Int
        public let recordedAudioSegmentCount: Int
        public let lastPresentationTimeSeconds: Double?
        public let pausedAtSeconds: Double?
        public let hasRecordedClip: Bool

        public init(snapshot: RecorderSink.Snapshot) {
            self.stateDescription = String(describing: snapshot.state)
            self.outputURL = snapshot.outputURL
            self.recordedClipURL = snapshot.recordedClipURL
            self.totalDurationSeconds = snapshot.totalDuration.seconds
            self.currentClipDurationSeconds = snapshot.currentClipDuration.seconds
            self.clipCount = snapshot.clipCount
            self.currentClipHasStarted = snapshot.currentClipHasStarted
            self.currentClipHasVideo = snapshot.currentClipHasVideo
            self.currentClipHasAudio = snapshot.currentClipHasAudio
            self.recordedVideoSegmentCount = snapshot.recordedVideoSegmentCount
            self.recordedAudioSegmentCount = snapshot.recordedAudioSegmentCount
            self.lastPresentationTimeSeconds = snapshot.lastPresentationTime?.seconds
            self.pausedAtSeconds = snapshot.pausedAt?.seconds
            self.hasRecordedClip = snapshot.hasRecordedClip
        }
    }

    public struct Manifest: Equatable, Sendable, Codable {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineStateDescription: String
        public let recorderStateDescription: String
        public let sourceSnapshot: PreviewPipeline.ManifestSourceSnapshot?
        public let recorderSnapshot: ManifestRecorderSnapshot
#if canImport(UIKit) && !os(watchOS)
        public let cameraSourceStateDescription: String?
        public let cameraSourcePositionDescription: String?
        public let cameraSourceAuthorizationStatusDescription: String?
        public let cameraSourceIsPaused: Bool?
        public let cameraSourceCaptureModeDescription: String?
        public let cameraSourceLastFrameIndex: Int64?
        public let cameraSourceLastPresentationTimeSeconds: Double?
        public let cameraSourceLastMediaType: String?
#endif
        public let clipCount: Int
        public let totalDurationSeconds: Double
        public let currentClipDurationSeconds: Double
        public let hasRecordedClip: Bool
        public let currentClipHasStarted: Bool
        public let currentClipHasVideo: Bool
        public let currentClipHasAudio: Bool
        public let recordedVideoSegmentCount: Int
        public let recordedAudioSegmentCount: Int
        public let lastErrorDescription: String?
    }

    public struct Snapshot {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineState: MediaPipeline.State
        public let recorderState: RecorderSink.State
        public let sourceSnapshot: MediaSourceSnapshot?
        public let recorderSnapshot: RecorderSink.Snapshot
#if canImport(UIKit) && !os(watchOS)
        public let cameraSourceSnapshot: CameraSource.Snapshot?
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
    }

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

    public var snapshot: Snapshot {
        let recorderSnapshot = recorderSink.snapshot
#if canImport(UIKit) && !os(watchOS)
        return Snapshot(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            recorderState: recorderSink.state,
            sourceSnapshot: pipeline.summary.sourceSnapshot,
            recorderSnapshot: recorderSnapshot,
            cameraSourceSnapshot: cameraSource?.snapshot,
            clipCount: recorderSnapshot.clipCount,
            totalDuration: recorderSnapshot.totalDuration,
            currentClipDuration: recorderSnapshot.currentClipDuration,
            hasRecordedClip: recorderSnapshot.hasRecordedClip,
            currentClipHasStarted: recorderSnapshot.currentClipHasStarted,
            currentClipHasVideo: recorderSnapshot.currentClipHasVideo,
            currentClipHasAudio: recorderSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: recorderSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: recorderSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: pipeline.lastErrorDescription
        )
#else
        return Snapshot(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            recorderState: recorderSink.state,
            sourceSnapshot: pipeline.summary.sourceSnapshot,
            recorderSnapshot: recorderSnapshot,
            clipCount: recorderSnapshot.clipCount,
            totalDuration: recorderSnapshot.totalDuration,
            currentClipDuration: recorderSnapshot.currentClipDuration,
            hasRecordedClip: recorderSnapshot.hasRecordedClip,
            currentClipHasStarted: recorderSnapshot.currentClipHasStarted,
            currentClipHasVideo: recorderSnapshot.currentClipHasVideo,
            currentClipHasAudio: recorderSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: recorderSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: recorderSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: pipeline.lastErrorDescription
        )
#endif
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
#if canImport(UIKit) && !os(watchOS)
        return Summary(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorCount: currentSnapshot.processorCount,
            pipelineState: currentSnapshot.pipelineState,
            recorderState: currentSnapshot.recorderState,
            sourceSnapshot: currentSnapshot.sourceSnapshot,
            cameraSourceState: currentSnapshot.cameraSourceSnapshot?.state,
            cameraSourcePosition: currentSnapshot.cameraSourceSnapshot?.position,
            cameraSourceAuthorizationStatus: currentSnapshot.cameraSourceSnapshot?.authorizationStatus,
            cameraSourceIsPaused: currentSnapshot.cameraSourceSnapshot?.isPaused,
            cameraSourceCaptureMode: currentSnapshot.cameraSourceSnapshot?.captureMode,
            cameraSourceLastFrameIndex: currentSnapshot.cameraSourceSnapshot?.lastFrameIndex,
            cameraSourceLastPresentationTime: currentSnapshot.cameraSourceSnapshot?.lastPresentationTime,
            cameraSourceLastMediaType: currentSnapshot.cameraSourceSnapshot?.lastMediaType,
            clipCount: currentSnapshot.clipCount,
            totalDuration: currentSnapshot.totalDuration,
            currentClipDuration: currentSnapshot.currentClipDuration,
            hasRecordedClip: currentSnapshot.hasRecordedClip,
            currentClipHasStarted: currentSnapshot.currentClipHasStarted,
            currentClipHasVideo: currentSnapshot.currentClipHasVideo,
            currentClipHasAudio: currentSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: currentSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: currentSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
#else
        return Summary(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorCount: currentSnapshot.processorCount,
            pipelineState: currentSnapshot.pipelineState,
            recorderState: currentSnapshot.recorderState,
            sourceSnapshot: currentSnapshot.sourceSnapshot,
            clipCount: currentSnapshot.clipCount,
            totalDuration: currentSnapshot.totalDuration,
            currentClipDuration: currentSnapshot.currentClipDuration,
            hasRecordedClip: currentSnapshot.hasRecordedClip,
            currentClipHasStarted: currentSnapshot.currentClipHasStarted,
            currentClipHasVideo: currentSnapshot.currentClipHasVideo,
            currentClipHasAudio: currentSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: currentSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: currentSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: currentSnapshot.lastErrorDescription
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

    public var manifest: Manifest {
        let recorderSnapshot = recorderSink.snapshot
        let currentSnapshot = snapshot
#if canImport(UIKit) && !os(watchOS)
        return Manifest(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorCount: currentSnapshot.processorCount,
            pipelineStateDescription: String(describing: currentSnapshot.pipelineState),
            recorderStateDescription: String(describing: currentSnapshot.recorderState),
            sourceSnapshot: currentSnapshot.sourceSnapshot.map(PreviewPipeline.ManifestSourceSnapshot.init(snapshot:)),
            recorderSnapshot: ManifestRecorderSnapshot(snapshot: recorderSnapshot),
            cameraSourceStateDescription: currentSnapshot.cameraSourceSnapshot.map { String(describing: $0.state) },
            cameraSourcePositionDescription: currentSnapshot.cameraSourceSnapshot.map { String(describing: $0.position) },
            cameraSourceAuthorizationStatusDescription: currentSnapshot.cameraSourceSnapshot.map { String(describing: $0.authorizationStatus) },
            cameraSourceIsPaused: currentSnapshot.cameraSourceSnapshot?.isPaused,
            cameraSourceCaptureModeDescription: currentSnapshot.cameraSourceSnapshot.map { String(describing: $0.captureMode) },
            cameraSourceLastFrameIndex: currentSnapshot.cameraSourceSnapshot?.lastFrameIndex,
            cameraSourceLastPresentationTimeSeconds: currentSnapshot.cameraSourceSnapshot?.lastPresentationTime?.seconds,
            cameraSourceLastMediaType: currentSnapshot.cameraSourceSnapshot?.lastMediaType,
            clipCount: currentSnapshot.clipCount,
            totalDurationSeconds: currentSnapshot.totalDuration.seconds,
            currentClipDurationSeconds: currentSnapshot.currentClipDuration.seconds,
            hasRecordedClip: currentSnapshot.hasRecordedClip,
            currentClipHasStarted: currentSnapshot.currentClipHasStarted,
            currentClipHasVideo: currentSnapshot.currentClipHasVideo,
            currentClipHasAudio: currentSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: currentSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: currentSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
#else
        return Manifest(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorCount: currentSnapshot.processorCount,
            pipelineStateDescription: String(describing: currentSnapshot.pipelineState),
            recorderStateDescription: String(describing: currentSnapshot.recorderState),
            sourceSnapshot: currentSnapshot.sourceSnapshot.map(PreviewPipeline.ManifestSourceSnapshot.init(snapshot:)),
            recorderSnapshot: ManifestRecorderSnapshot(snapshot: recorderSnapshot),
            clipCount: currentSnapshot.clipCount,
            totalDurationSeconds: currentSnapshot.totalDuration.seconds,
            currentClipDurationSeconds: currentSnapshot.currentClipDuration.seconds,
            hasRecordedClip: currentSnapshot.hasRecordedClip,
            currentClipHasStarted: currentSnapshot.currentClipHasStarted,
            currentClipHasVideo: currentSnapshot.currentClipHasVideo,
            currentClipHasAudio: currentSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: currentSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: currentSnapshot.recordedAudioSegmentCount,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
#endif
    }

    public init(
        source: MediaSource,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = [],
        recorderConfiguration: RecorderSink.Configuration = .init()
    ) throws {
        self.source = source
        self.recorderSink = try RecorderSink(outputURL: outputURL, fileType: fileType, configuration: recorderConfiguration)
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
        let recorderConfiguration = RecorderSink.Configuration(
            dimensions: configuration.video.dimensions,
            bitRate: configuration.video.bitRate,
            codec: configuration.video.codec,
            scalingMode: configuration.video.scalingMode,
            transform: configuration.video.transform,
            includesAudio: configuration.captureMode.includesAudio,
            audioBitRate: configuration.audio.bitRate,
            audioSampleRate: configuration.audio.sampleRate,
            audioChannelCount: configuration.audio.channelCount
        )
        try self.init(
            source: source,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors,
            recorderConfiguration: recorderConfiguration
        )
    }

    var cameraSource: CameraSource? {
        source as? CameraSource
    }
}
#endif
