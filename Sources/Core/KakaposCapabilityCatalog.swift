//
//  KakaposCapabilityCatalog.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public enum KakaposCapabilityBoard: String, CaseIterable, Sendable {
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
            return "Offline export and compatibility entry points for VideoX, Provider, and instructions."
        case .preview:
            return "Player frame sourcing and preview routing through PreviewPipeline, MediaPipeline, and PreviewSink."
        case .record:
            return "Camera capture, recording, and sink lifecycle through RecordingPipeline, CameraSource, and RecorderSink."
        case .timeline:
            return "Layer composition, keyframes, transitions, and audio mix through TimelinePipeline and TimelineComposition."
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
            return ["TimelinePipeline", "TimelineComposition", "ClipLayer", "ImageLayer", "AudioLayer", "EffectLayer", "GroupLayer", "Transition", "KeyframeAnimation"]
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
            return ["TimelinePipeline", "TimelineComposition"]
        }
    }
}

public struct KakaposCapabilityBoardInfo: Sendable, Hashable {
    public let board: KakaposCapabilityBoard
    public let displayName: String
    public let summary: String
    public let primaryTypes: [String]
    public let starterTypes: [String]
}

public enum KakaposCapabilityCatalog {
    public static let boards: [KakaposCapabilityBoardInfo] = KakaposCapabilityBoard.allCases.map {
        KakaposCapabilityBoardInfo(
            board: $0,
            displayName: $0.displayName,
            summary: $0.summary,
            primaryTypes: $0.primaryTypes,
            starterTypes: $0.starterTypes
        )
    }

    public static func board(named name: String) -> KakaposCapabilityBoardInfo? {
        boards.first { $0.board.rawValue == name }
    }
}
