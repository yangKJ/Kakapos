//
//  KakaposSurface.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
@_exported import KakaposMediaCore
@_exported import KakaposVideo
@_exported import KakaposTimeline
@_exported import KakaposCamera

/// Lightweight public entry points for the four Kakapos boards.
///
/// This surface does not add new media behavior. It only groups the
/// existing engine types into a smaller, easier-to-scan entry layer.
public enum KakaposSurface {
    public struct Entry: Sendable {
        public let board: KakaposCapabilityBoardInfo
        public let section: KakaposSurfaceSection

        public var id: String {
            section.id
        }

        public var displayName: String {
            section.displayName
        }

        public var summary: String {
            section.summary
        }

        public var usageHint: String {
            section.usageHint
        }

        public var primaryTypes: [String] {
            section.primaryTypes
        }

        public var starterTypes: [String] {
            section.starterTypes
        }

        public var primaryTypesText: String {
            section.primaryTypesText
        }

        public var starterTypesText: String {
            section.starterTypesText
        }
    }

    public static var sections: [KakaposSurfaceSection] {
        KakaposCapabilityCatalog.boards.map(KakaposSurfaceSection.init(info:))
    }

    public static var entries: [Entry] {
        KakaposCapabilityCatalog.boards.compactMap { info in
            guard let section = section(info.board) else { return nil }
            return Entry(board: info, section: section)
        }
    }

    public static var starterEntries: [Entry] {
        entries
    }

    public static var boards: [KakaposCapabilityBoardInfo] {
        KakaposCapabilityCatalog.boards
    }

    public static var starterBoards: [KakaposCapabilityBoardInfo] {
        KakaposCapabilityCatalog.starterBoards
    }

    public static var guide: KakaposSurfaceGuide {
        KakaposCapabilityCatalog.guide
    }

    public static var manifest: KakaposSurfaceManifest {
        KakaposCapabilityCatalog.manifest
    }

    public static var engines: [KakaposEngineInfo] {
        KakaposEngineCatalog.engines
    }

    public static var publicEngines: [KakaposEngineInfo] {
        KakaposEngineCatalog.publicEngines
    }

    public static func engine(named name: String) -> KakaposEngineInfo? {
        KakaposEngineCatalog.engine(named: name)
    }

    public static func board(named name: String) -> KakaposCapabilityBoardInfo? {
        KakaposCapabilityCatalog.board(named: name)
    }

    public static func board(_ board: KakaposCapabilityBoard) -> KakaposCapabilityBoardInfo? {
        KakaposCapabilityCatalog.board(named: board.rawValue)
    }

    public static func section(named name: String) -> KakaposSurfaceSection? {
        sections.first { $0.board.rawValue == name }
    }

    public static func section(_ board: KakaposCapabilityBoard) -> KakaposSurfaceSection? {
        sections.first { $0.board == board }
    }

    public static func entry(_ board: KakaposCapabilityBoard) -> Entry? {
        guard let boardInfo = KakaposSurface.board(board), let section = KakaposSurface.section(board) else {
            return nil
        }
        return Entry(board: boardInfo, section: section)
    }

    public static var exportBoard: ExportBoard {
        ExportBoard()
    }

    public static var previewBoard: PreviewBoard {
        PreviewBoard()
    }

    public static var recordBoard: RecordBoard {
        RecordBoard()
    }

    public static var timelineBoard: TimelineBoard {
        TimelineBoard()
    }

    public static func export(provider: VideoX.Provider) -> VideoX {
        exportBoard.export(provider: provider)
    }

    public static func exportTask(
        provider: VideoX.Provider,
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> VideoX.ExportTask {
        try exportBoard.exportTask(provider: provider, options: options, instructions: instructions)
    }

    public static func preview(
        source: MediaSource,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        previewBoard.preview(
            source: source,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

#if canImport(UIKit) || os(macOS)
    public static func preview(
        player: AVPlayer,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        previewBoard.preview(
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
        previewBoard.preview(
            asset: asset,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }

    public static func preview(
        recordedClip: RecordedClip,
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline? {
        previewBoard.preview(
            recordedClip: recordedClip,
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
        try recordBoard.record(
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
        try recordBoard.record(
            configuration: configuration,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
    }

    public static func camera(
        configuration: CameraCaptureConfiguration = .init()
    ) throws -> CameraEngine {
        try recordBoard.camera(configuration: configuration)
    }
#endif

    public static func timeline(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = []
    ) -> TimelinePipeline {
        timelineBoard.timeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        )
    }

    public static func timeline(
        recordedClip: RecordedClip,
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> TimelinePipeline? {
        timelineBoard.timeline(
            recordedClip: recordedClip,
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )
    }

    public static func timelineExportTask(
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
        timelineBoard.timelineExportTask(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions,
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    public static func timelineExportTask(
        recordedClip: RecordedClip,
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = []
    ) -> TimelineExportTask? {
        timelineBoard.timelineExportTask(
            recordedClip: recordedClip,
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel,
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    public struct ExportBoard: Sendable {
        public var board: KakaposCapabilityBoard { .export }
        public var displayName: String { board.displayName }
        public var summary: String { board.summary }
        public var usageHint: String { board.usageHint }
        public var primaryTypes: [String] { board.primaryTypes }
        public var starterTypes: [String] { board.starterTypes }

        public func export(provider: VideoX.Provider) -> VideoX {
            KakaposEntryPointFactory.export(provider: provider)
        }

        public func exportTask(
            provider: VideoX.Provider,
            options: [VideoX.Option: Any] = [:],
            instructions: [CompositionInstruction]
        ) throws -> VideoX.ExportTask {
            try KakaposEntryPointFactory.exportTask(provider: provider, options: options, instructions: instructions)
        }
    }

    public struct PreviewBoard: Sendable {
        public var board: KakaposCapabilityBoard { .preview }
        public var displayName: String { board.displayName }
        public var summary: String { board.summary }
        public var usageHint: String { board.usageHint }
        public var primaryTypes: [String] { board.primaryTypes }
        public var starterTypes: [String] { board.starterTypes }

        public func preview(
            source: MediaSource,
            processors: [FrameProcessor] = [],
            callbackQueue: DispatchQueue = .main,
            handler: @escaping PreviewSink.Handler
        ) -> PreviewPipeline {
            KakaposEntryPointFactory.preview(
                source: source,
                processors: processors,
                callbackQueue: callbackQueue,
                handler: handler
            )
        }

    #if canImport(UIKit) || os(macOS)
        public func preview(
            player: AVPlayer,
            preferredFramesPerSecond: Int = 30,
            processors: [FrameProcessor] = [],
            callbackQueue: DispatchQueue = .main,
            handler: @escaping PreviewSink.Handler
        ) -> PreviewPipeline {
            KakaposEntryPointFactory.preview(
                player: player,
                preferredFramesPerSecond: preferredFramesPerSecond,
                processors: processors,
                callbackQueue: callbackQueue,
                handler: handler
            )
        }

        public func preview(
            asset: AVAsset,
            preferredFramesPerSecond: Int = 30,
            processors: [FrameProcessor] = [],
            callbackQueue: DispatchQueue = .main,
            handler: @escaping PreviewSink.Handler
        ) -> PreviewPipeline {
            KakaposEntryPointFactory.preview(
                asset: asset,
                preferredFramesPerSecond: preferredFramesPerSecond,
                processors: processors,
                callbackQueue: callbackQueue,
                handler: handler
            )
        }

        public func preview(
            recordedClip: RecordedClip,
            preferredFramesPerSecond: Int = 30,
            processors: [FrameProcessor] = [],
            callbackQueue: DispatchQueue = .main,
            handler: @escaping PreviewSink.Handler
        ) -> PreviewPipeline? {
            KakaposEntryPointFactory.preview(
                recordedClip: recordedClip,
                preferredFramesPerSecond: preferredFramesPerSecond,
                processors: processors,
                callbackQueue: callbackQueue,
                handler: handler
            )
        }
    #endif
    }

    public struct RecordBoard: Sendable {
        public var board: KakaposCapabilityBoard { .record }
        public var displayName: String { board.displayName }
        public var summary: String { board.summary }
        public var usageHint: String { board.usageHint }
        public var primaryTypes: [String] { board.primaryTypes }
        public var starterTypes: [String] { board.starterTypes }

        public func record(
            source: MediaSource,
            outputURL: URL,
            fileType: AVFileType = .mp4,
            processors: [FrameProcessor] = []
        ) throws -> RecordingPipeline {
            try KakaposEntryPointFactory.record(
                source: source,
                outputURL: outputURL,
                fileType: fileType,
                processors: processors
            )
        }

    #if canImport(UIKit) && !os(watchOS)
        public func record(
            configuration: CameraSourceConfiguration = .init(),
            outputURL: URL,
            fileType: AVFileType = .mp4,
            processors: [FrameProcessor] = []
        ) throws -> RecordingPipeline {
            try KakaposEntryPointFactory.record(
                configuration: configuration,
                outputURL: outputURL,
                fileType: fileType,
                processors: processors
            )
        }

        public func camera(
            configuration: CameraCaptureConfiguration = .init()
        ) throws -> CameraEngine {
            try KakaposEntryPointFactory.camera(configuration: configuration)
        }
    #endif
    }

    public struct TimelineBoard: Sendable {
        public var board: KakaposCapabilityBoard { .timeline }
        public var displayName: String { board.displayName }
        public var summary: String { board.summary }
        public var usageHint: String { board.usageHint }
        public var primaryTypes: [String] { board.primaryTypes }
        public var starterTypes: [String] { board.starterTypes }

        public func timeline(
            renderSize: CGSize = CGSize(width: 720, height: 1280),
            frameDuration: CMTime = CMTime(value: 1, timescale: 30),
            layers: [TimelineLayer] = [],
            transitions: [Transition] = []
        ) -> TimelinePipeline {
            KakaposEntryPointFactory.timeline(
                renderSize: renderSize,
                frameDuration: frameDuration,
                layers: layers,
                transitions: transitions
            )
        }

        public func timeline(
            recordedClip: RecordedClip,
            renderSize: CGSize = CGSize(width: 720, height: 1280),
            frameDuration: CMTime = CMTime(value: 1, timescale: 30),
            startTime: CMTime = .zero,
            sourceTimeRange: CMTimeRange? = nil,
            layerLevel: Int = 0
        ) -> TimelinePipeline? {
            KakaposEntryPointFactory.timeline(
                recordedClip: recordedClip,
                renderSize: renderSize,
                frameDuration: frameDuration,
                startTime: startTime,
                sourceTimeRange: sourceTimeRange,
                layerLevel: layerLevel
            )
        }

        public func timelineExportTask(
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
            KakaposEntryPointFactory.timelineExportTask(
                renderSize: renderSize,
                frameDuration: frameDuration,
                layers: layers,
                transitions: transitions,
                outputURL: outputURL,
                fileType: fileType,
                shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
                metadata: metadata,
                videoProcessors: videoProcessors
            )
        }

        public func timelineExportTask(
            recordedClip: RecordedClip,
            renderSize: CGSize = CGSize(width: 720, height: 1280),
            frameDuration: CMTime = CMTime(value: 1, timescale: 30),
            startTime: CMTime = .zero,
            sourceTimeRange: CMTimeRange? = nil,
            layerLevel: Int = 0,
            outputURL: URL,
            fileType: AVFileType = .mp4,
            shouldOptimizeForNetworkUse: Bool = true,
            metadata: [AVMetadataItem] = [],
            videoProcessors: [FrameProcessor] = []
        ) -> TimelineExportTask? {
            KakaposEntryPointFactory.timelineExportTask(
                recordedClip: recordedClip,
                renderSize: renderSize,
                frameDuration: frameDuration,
                startTime: startTime,
                sourceTimeRange: sourceTimeRange,
                layerLevel: layerLevel,
                outputURL: outputURL,
                fileType: fileType,
                shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
                metadata: metadata,
                videoProcessors: videoProcessors
            )
        }
    }
}
