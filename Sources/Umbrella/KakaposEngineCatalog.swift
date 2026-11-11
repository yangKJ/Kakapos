//
//  KakaposEngineCatalog.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

public enum KakaposEngine: String, CaseIterable, Sendable, Codable {
    case mediaCore
    case video
    case camera
    case timeline

    public var displayName: String {
        switch self {
        case .mediaCore:
            return "Media Core"
        case .video:
            return "Video Engine"
        case .camera:
            return "Camera Engine"
        case .timeline:
            return "Timeline Engine"
        }
    }

    public var summary: String {
        switch self {
        case .mediaCore:
            return "Shared frame, processor, source, sink, and pipeline contracts."
        case .video:
            return "Asset, player-frame preview, offline export, and export instruction workflows."
        case .camera:
            return "Realtime camera capture, processed preview, recording, device control, and advanced outputs."
        case .timeline:
            return "Layered composition, keyframes, transitions, audio mix, and timeline export."
        }
    }

    public var boards: [KakaposCapabilityBoard] {
        switch self {
        case .mediaCore:
            return [.preview, .record, .timeline, .export]
        case .video:
            return [.export, .preview]
        case .camera:
            return [.preview, .record]
        case .timeline:
            return [.timeline]
        }
    }

    public var primaryTypes: [String] {
        switch self {
        case .mediaCore:
            return ["FrameProcessor", "MediaFrame", "FrameMetadata", "MediaSource", "MediaSink", "MediaPipeline", "MediaProcessorChain"]
        case .video:
            return ["VideoX", "ReaderWriterExportJob", "PlayerFrameSource", "PreviewPipeline", "Provider", "Instruction", "FilterInstruction", "RotateInstruction", "WatermarkInstruction"]
        case .camera:
            return ["CameraEngine", "CameraSource", "CameraDeviceController", "CameraPreviewController", "CameraRecordingController", "CameraAdvancedOutput", "RecordingPipeline", "PreviewSink", "RecorderSink", "RecordingSession"]
        case .timeline:
            return ["TimelinePipeline", "TimelineExportTask", "TimelineComposition", "ClipLayer", "ImageLayer", "AudioLayer", "EffectLayer", "GroupLayer", "Transition", "KeyframeAnimation"]
        }
    }

    public var boundary: String {
        switch self {
        case .mediaCore:
            return "Foundation layer only; it should not own camera, export, or timeline product workflows."
        case .video:
            return "Export instructions belong here as the offline export instruction layer."
        case .camera:
            return "Camera preview, recording, device control, depth, metadata, portrait, AR, and multicam belong here, but player preview remains part of video workflows."
        case .timeline:
            return "Timeline compiles processor plans and export tasks without becoming a filter-kernel layer."
        }
    }
}

public struct KakaposEngineInfo: Sendable, Hashable, Codable {
    public let engine: KakaposEngine
    public let displayName: String
    public let summary: String
    public let boards: [KakaposCapabilityBoard]
    public let primaryTypes: [String]
    public let boundary: String

    public var id: String {
        engine.rawValue
    }

    public var boardNames: [String] {
        boards.map(\.displayName)
    }

    public var primaryTypesText: String {
        primaryTypes.joined(separator: " · ")
    }
}

public enum KakaposEngineCatalog {
    public static let engines: [KakaposEngineInfo] = KakaposEngine.allCases.map {
        KakaposEngineInfo(
            engine: $0,
            displayName: $0.displayName,
            summary: $0.summary,
            boards: $0.boards,
            primaryTypes: $0.primaryTypes,
            boundary: $0.boundary
        )
    }

    public static var publicEngines: [KakaposEngineInfo] {
        engines.filter { $0.engine != .mediaCore }
    }

    public static func engine(named name: String) -> KakaposEngineInfo? {
        engines.first { $0.engine.rawValue == name }
    }
}
