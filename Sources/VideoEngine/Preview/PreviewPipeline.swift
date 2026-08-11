//
//  PreviewPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import AVFoundation

struct PreviewSendableBox<T>: @unchecked Sendable {
    let value: T
}

public final class PreviewPipeline: @unchecked Sendable {
    public struct ManifestSourceSnapshot: Equatable, Sendable, Codable {
        public let stateDescription: String
        public let lastFrameIndex: Int64?
        public let lastPresentationTimeSeconds: Double?
        public let lastSourceTimeSeconds: Double?
        public let lastErrorDescription: String?
        public let details: [String: String]

        public init(snapshot: MediaSourceSnapshot) {
            self.stateDescription = snapshot.stateDescription
            self.lastFrameIndex = snapshot.lastFrameIndex
            self.lastPresentationTimeSeconds = snapshot.lastPresentationTime?.seconds
            self.lastSourceTimeSeconds = snapshot.lastSourceTime?.seconds
            self.lastErrorDescription = snapshot.lastErrorDescription
            self.details = snapshot.details
        }
    }

    public struct Manifest: Equatable, Sendable, Codable {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineStateDescription: String
        public let previewStateDescription: String
        public let playerSourceStateDescription: String?
        public let playerSourceGeneration: Int64?
        public let playerSourceFrameIndex: Int64?
        public let playerSourceLastFrameRequestReason: String?
        public let sourceSnapshot: ManifestSourceSnapshot?
        public let lastFrameIndex: Int64?
        public let lastPresentationTimeSeconds: Double?
        public let lastSourceTimeSeconds: Double?
        public let lastFrameRequestReason: String?
        public let pendingFrameIndex: Int64?
        public let pendingFramePresentationTimeSeconds: Double?
        public let pendingFrameSourceTimeSeconds: Double?
        public let pendingFrameRequestReason: String?
        public let lastErrorDescription: String?
    }

    public struct Summary {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineState: MediaPipeline.State
        public let previewState: PreviewSink.State
        public let playerSourceState: PlayerFrameSource.State?
        public let playerSourceGeneration: Int64?
        public let playerSourceFrameIndex: Int64?
        public let playerSourceLastFrameRequestReason: String?
        public let sourceSnapshot: MediaSourceSnapshot?
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastSourceTime: CMTime?
        public let lastFrameRequestReason: String?
        public let pendingFrameIndex: Int64?
        public let pendingFramePresentationTime: CMTime?
        public let pendingFrameSourceTime: CMTime?
        public let pendingFrameRequestReason: String?
        public let lastErrorDescription: String?

        public var summaryText: String {
            var text = "source \(sourceTypeName) · processors \(processorCount) · pipeline \(pipelineState) · preview \(previewState)"
            if let sourceSnapshot {
                text += " · sourceSnapshot \(sourceSnapshot.summaryText)"
            }
            if let lastFrameIndex {
                text += " · frame \(lastFrameIndex)"
            }
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let lastSourceTime {
                text += " · sourceTime \(String(format: "%.2fs", lastSourceTime.seconds))"
            }
            if let lastFrameRequestReason {
                text += " · reason \(lastFrameRequestReason)"
            }
            if let pendingFrameIndex, let pendingFrameRequestReason {
                text += " · pendingFrame \(pendingFrameIndex)"
                if let pendingFramePresentationTime {
                    text += " · pendingPresentation \(String(format: "%.2fs", pendingFramePresentationTime.seconds))"
                }
                if let pendingFrameSourceTime {
                    text += " · pendingSourceTime \(String(format: "%.2fs", pendingFrameSourceTime.seconds))"
                }
                text += " · pendingReason \(pendingFrameRequestReason)"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }
    }

    public let source: MediaSource
    public let previewSink: PreviewSink
    public let pipeline: MediaPipeline

    public var processors: [FrameProcessor] {
        get { pipeline.processors }
        set { pipeline.processors = newValue }
    }

    public var state: MediaPipeline.State {
        pipeline.state
    }

    public var summary: Summary {
        let playerSummary = playerSource?.summary
        return Summary(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            previewState: previewSink.state,
            playerSourceState: playerSummary?.state,
            playerSourceGeneration: playerSummary?.generation,
            playerSourceFrameIndex: playerSummary?.frameIndex,
            playerSourceLastFrameRequestReason: playerSummary?.lastFrameRequestReason,
            sourceSnapshot: pipeline.summary.sourceSnapshot,
            lastFrameIndex: previewSink.lastFrame?.metadata.frameIndex,
            lastPresentationTime: previewSink.lastFrame?.metadata.presentationTime,
            lastSourceTime: previewSink.lastFrame?.metadata.sourceTime,
            lastFrameRequestReason: previewSink.summary.lastFrameRequestReason,
            pendingFrameIndex: previewSink.summary.pendingFrameIndex,
            pendingFramePresentationTime: previewSink.summary.pendingFramePresentationTime,
            pendingFrameSourceTime: previewSink.summary.pendingFrameSourceTime,
            pendingFrameRequestReason: previewSink.summary.pendingFrameRequestReason,
            lastErrorDescription: pipeline.lastErrorDescription
        )
    }

    public var lastErrorDescription: String? {
        pipeline.lastErrorDescription
    }

    public var summaryText: String {
        summary.summaryText
    }

    public var manifest: Manifest {
        let playerSummary = playerSource?.summary
        let previewSnapshot = previewSink.snapshot
        let pipelineSummary = pipeline.summary
        return Manifest(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineStateDescription: String(describing: pipeline.state),
            previewStateDescription: String(describing: previewSink.state),
            playerSourceStateDescription: playerSummary.map { String(describing: $0.state) },
            playerSourceGeneration: playerSummary?.generation,
            playerSourceFrameIndex: playerSummary?.frameIndex,
            playerSourceLastFrameRequestReason: playerSummary?.lastFrameRequestReason,
            sourceSnapshot: pipelineSummary.sourceSnapshot.map(ManifestSourceSnapshot.init(snapshot:)),
            lastFrameIndex: previewSnapshot.lastFrameIndex,
            lastPresentationTimeSeconds: previewSnapshot.lastPresentationTime?.seconds,
            lastSourceTimeSeconds: previewSnapshot.lastSourceTime?.seconds,
            lastFrameRequestReason: previewSnapshot.lastFrameRequestReason,
            pendingFrameIndex: previewSnapshot.pendingFrameIndex,
            pendingFramePresentationTimeSeconds: previewSnapshot.pendingFramePresentationTime?.seconds,
            pendingFrameSourceTimeSeconds: previewSnapshot.pendingFrameSourceTime?.seconds,
            pendingFrameRequestReason: previewSnapshot.pendingFrameRequestReason,
            lastErrorDescription: pipeline.lastErrorDescription
        )
    }

    public var sourceSnapshot: MediaSourceSnapshot? {
        summary.sourceSnapshot
    }

    public var previewSnapshot: PreviewSink.Snapshot {
        previewSink.snapshot
    }

    public var playerSourceSnapshot: PlayerFrameSource.Snapshot? {
        playerSource?.snapshot
    }

#if canImport(UIKit) || os(macOS)
    public var playerSourceState: PlayerFrameSource.State? {
        playerSource?.summary.state
    }

    public var playerSourceSummary: PlayerFrameSource.Summary? {
        playerSource?.summary
    }

    public var playerSourceGeneration: Int64? {
        playerSource?.summary.generation
    }

    public var playerSourceFrameIndex: Int64? {
        playerSource?.summary.frameIndex
    }
#endif

    public init(
        source: MediaSource,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        controlsSourceLifecycle: Bool = true,
        handler: @escaping PreviewSink.Handler
    ) {
        self.source = source
        self.previewSink = PreviewSink(callbackQueue: callbackQueue, handler: handler)
        self.pipeline = MediaPipeline(
            source: source,
            processors: processors,
            sinks: [previewSink],
            deliveryPolicy: .latestOnly,
            controlsSourceLifecycle: controlsSourceLifecycle
        )
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

#if canImport(UIKit) || os(macOS)
public extension PreviewPipeline {
    convenience init?(
        recordedClip: RecordedClip,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) {
        guard let asset = recordedClip.asset else {
            return nil
        }
        self.init(
            asset: asset,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

    convenience init(
        asset: AVAsset,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) {
        let assetBox = PreviewSendableBox(value: asset)
        let playerItem = AVPlayerItem(asset: assetBox.value)
        let player = AVPlayer(playerItem: playerItem)
        self.init(
            player: player,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

    convenience init(
        player: AVPlayer,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) {
        let source = PlayerFrameSource(player: player, preferredFramesPerSecond: preferredFramesPerSecond)
        self.init(source: source, processors: processors, callbackQueue: callbackQueue, handler: handler)
    }

    var playerSource: PlayerFrameSource? {
        source as? PlayerFrameSource
    }

    func requestFrameUpdate() {
        (source as? PlayerFrameSource)?.requestFrameUpdate()
    }

    func refreshCurrentFrameIfNeeded() {
        (source as? PlayerFrameSource)?.refreshCurrentFrameIfNeeded()
    }

    func seek(
        to time: CMTime,
        toleranceBefore: CMTime = .zero,
        toleranceAfter: CMTime = .zero,
        completion: ((Bool) -> Void)? = nil
    ) {
        (source as? PlayerFrameSource)?.seek(
            to: time,
            toleranceBefore: toleranceBefore,
            toleranceAfter: toleranceAfter,
            completion: completion
        )
    }
}
#endif
