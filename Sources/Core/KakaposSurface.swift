//
//  KakaposSurface.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

/// Lightweight public entry points for the four Kakapos boards.
///
/// This surface does not add new media behavior. It only groups the
/// existing engine types into a smaller, easier-to-scan entry layer.
public enum KakaposSurface {
    public static var boards: [KakaposCapabilityBoardInfo] {
        KakaposCapabilityCatalog.boards
    }

    public static func board(named name: String) -> KakaposCapabilityBoardInfo? {
        KakaposCapabilityCatalog.board(named: name)
    }

    public static func export(provider: VideoX.Provider) -> VideoX {
        KakaposBoards.export(provider: provider)
    }

    public static func exportTask(
        provider: VideoX.Provider,
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> VideoX.ExportTask {
        try KakaposBoards.exportTask(provider: provider, options: options, instructions: instructions)
    }

    public static func preview(
        source: MediaSource,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        KakaposBoards.preview(
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
        KakaposBoards.preview(
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
        KakaposBoards.preview(
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
        try KakaposBoards.record(
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
        try KakaposBoards.record(
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
        KakaposBoards.timeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        )
    }
}
