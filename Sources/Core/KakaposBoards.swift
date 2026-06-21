//
//  KakaposBoards.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

/// Thin public entry points that keep Kakapos adoption lightweight.
///
/// These helpers do not add new media behavior. They only gather the four
/// starter boards around the existing engine types so external code can
/// begin from a smaller surface area.
@available(*, deprecated, message: "Use KakaposSurface as the recommended lightweight entry point.")
public enum KakaposBoards {
    public static func export(provider: VideoX.Provider) -> VideoX {
        VideoX(provider: provider)
    }

    public static func exportTask(
        provider: VideoX.Provider,
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> VideoX.ExportTask {
        try export(provider: provider).makeExportTask(options: options, instructions: instructions)
    }

    public static func preview(
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

#if canImport(UIKit)
    public static func preview(
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

    public static func preview(
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

    public static func record(
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
    public static func record(
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

    public static func timeline(
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
}
