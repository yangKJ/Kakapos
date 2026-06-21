//
//  KakaposEntryPointFactory.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

enum KakaposEntryPointFactory {
    static func export(provider: VideoX.Provider) -> VideoX {
        VideoX(provider: provider)
    }

    static func exportTask(
        provider: VideoX.Provider,
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> VideoX.ExportTask {
        try export(provider: provider).makeExportTask(options: options, instructions: instructions)
    }

    static func preview(
        source: MediaSource,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        PreviewPipeline(
            source: source,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

#if canImport(UIKit) || os(macOS)
    static func preview(
        player: AVPlayer,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        PreviewPipeline(
            player: player,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

    static func preview(
        asset: AVAsset,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        PreviewPipeline(
            asset: asset,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }
#endif

    static func record(
        source: MediaSource,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws -> RecordingPipeline {
        try RecordingPipeline(
            source: source,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
    }

#if canImport(UIKit) && !os(watchOS)
    static func record(
        configuration: CameraSourceConfiguration = .init(),
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws -> RecordingPipeline {
        try RecordingPipeline(
            configuration: configuration,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
    }
#endif

    static func timeline(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = []
    ) -> TimelinePipeline {
        TimelinePipeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        )
    }

    static func timelineExportTask(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = [],
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = []
    ) -> TimelineExportTask {
        timeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        ).makeExportTask(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }
}
