//
//  KakaposCapabilityCatalog.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public enum KakaposCapabilityBoard: String, CaseIterable, Sendable, Codable {
    case export
    case preview
    case record
    case timeline

    public var displayName: String {
        switch self {
        case .export:
            return "Export"
        case .preview:
            return "Preview"
        case .record:
            return "Record"
        case .timeline:
            return "Timeline"
        }
    }

    public var summary: String {
        switch self {
        case .export:
            return "Offline export for asset-based workflows."
        case .preview:
            return "Player-frame preview and custom source routing through a lightweight pipeline."
        case .record:
            return "Camera capture and recording with a stable session lifecycle."
        case .timeline:
            return "Layered composition, keyframes, transitions, and audio mix for export planning."
        }
    }

    public var usageHint: String {
        switch self {
        case .export:
            return "Start here when you already have an asset and need offline export."
        case .preview:
            return "Start here when you want player frames or a custom source to render into preview."
        case .record:
            return "Start here when you need camera capture or recording to file."
        case .timeline:
            return "Start here when you need layered composition and export planning."
        }
    }

    public var primaryTypes: [String] {
        switch self {
        case .export:
            return ["VideoX", "Provider", "Instruction", "FilterInstruction", "RotateInstruction", "WatermarkInstruction", "ReaderWriterExportJob"]
        case .preview:
            return ["PreviewPipeline", "PlayerFrameSource", "PreviewSink", "MediaPipeline", "MediaProcessorChain"]
        case .record:
            return ["RecordingPipeline", "CameraSource", "RecorderSink", "RecordingSession"]
        case .timeline:
            return ["TimelinePipeline", "TimelineExportTask", "TimelineComposition", "ClipLayer", "ImageLayer", "AudioLayer", "EffectLayer", "GroupLayer", "Transition", "KeyframeAnimation"]
        }
    }

    public var starterTypes: [String] {
        switch self {
        case .export:
            return ["VideoX", "ReaderWriterExportJob"]
        case .preview:
            return ["PreviewPipeline", "PlayerFrameSource", "PreviewSink"]
        case .record:
            return ["RecordingPipeline", "CameraSource", "RecorderSink"]
        case .timeline:
            return ["TimelinePipeline", "TimelineExportTask", "TimelineComposition"]
        }
    }
}

public struct KakaposCapabilityBoardInfo: Sendable, Hashable, Codable {
    public let board: KakaposCapabilityBoard
    public let displayName: String
    public let summary: String
    public let usageHint: String
    public let primaryTypes: [String]
    public let starterTypes: [String]
}

public enum KakaposCapabilityCatalog {
    public static let boards: [KakaposCapabilityBoardInfo] = KakaposCapabilityBoard.allCases.map {
        KakaposCapabilityBoardInfo(
            board: $0,
            displayName: $0.displayName,
            summary: $0.summary,
            usageHint: $0.usageHint,
            primaryTypes: $0.primaryTypes,
            starterTypes: $0.starterTypes
        )
    }

    public static var starterBoards: [KakaposCapabilityBoardInfo] {
        boards
    }

    public static var guide: KakaposSurfaceGuide {
        KakaposSurfaceGuide(boards: boards, starterBoards: starterBoards)
    }

    public static var manifest: KakaposSurfaceManifest {
        KakaposSurfaceManifest(
            boards: boards.map(KakaposSurfaceSection.init(info:)),
            starterBoards: starterBoards.map(KakaposSurfaceSection.init(info:)),
            guide: guide
        )
    }

    public static func board(named name: String) -> KakaposCapabilityBoardInfo? {
        boards.first { $0.board.rawValue == name }
    }
}
