//
//  PreviewPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class PreviewPipeline {
    public struct Summary {
        public let sourceTypeName: String
        public let processorCount: Int
        public let pipelineState: MediaPipeline.State
        public let previewState: PreviewSink.State
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastSourceTime: CMTime?
        public let lastFrameRequestReason: String?
        public let lastErrorDescription: String?

        public var summaryText: String {
            var text = "source \(sourceTypeName) · processors \(processorCount) · pipeline \(pipelineState) · preview \(previewState)"
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
        Summary(
            sourceTypeName: String(describing: type(of: source)),
            processorCount: processors.count,
            pipelineState: pipeline.state,
            previewState: previewSink.state,
            lastFrameIndex: previewSink.lastFrame?.metadata.frameIndex,
            lastPresentationTime: previewSink.lastFrame?.metadata.presentationTime,
            lastSourceTime: previewSink.lastFrame?.metadata.sourceTime,
            lastFrameRequestReason: previewSink.summary.lastFrameRequestReason,
            lastErrorDescription: pipeline.lastErrorDescription
        )
    }

    public var lastErrorDescription: String? {
        pipeline.lastErrorDescription
    }

    public var summaryText: String {
        summary.summaryText
    }

    public var sourceSnapshot: MediaSourceSnapshot? {
        pipeline.summary.sourceSnapshot
    }

#if canImport(UIKit)
    public var playerSourceState: PlayerFrameSource.State? {
        playerSource?.summary.state
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
        handler: @escaping PreviewSink.Handler
    ) {
        self.source = source
        self.previewSink = PreviewSink(callbackQueue: callbackQueue, handler: handler)
        self.pipeline = MediaPipeline(source: source, processors: processors, sinks: [previewSink])
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

#if canImport(UIKit)
public extension PreviewPipeline {
    convenience init(
        asset: AVAsset,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) {
        let playerItem = AVPlayerItem(asset: asset)
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
