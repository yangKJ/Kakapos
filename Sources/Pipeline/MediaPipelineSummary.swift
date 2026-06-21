//
//  MediaPipelineSummary.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public struct MediaPipelineSummary {
    public let sourceTypeName: String
    public let processorTypeNames: [String]
    public let sinkTypeNames: [String]
    public let state: MediaPipeline.State
    public let lastFrameIndex: Int64?
    public let lastPresentationTime: CMTime?
    public let lastSourceTime: CMTime?
    public let lastErrorDescription: String?

    public var summaryText: String {
        var text = "source \(sourceTypeName) · processors \(processorTypeNames.count) · sinks \(sinkTypeNames.count) · state \(state)"
        if let lastFrameIndex {
            text += " · frame \(lastFrameIndex)"
        }
        if let lastPresentationTime {
            text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
        }
        if let lastSourceTime {
            text += " · sourceTime \(String(format: "%.2fs", lastSourceTime.seconds))"
        }
        if let lastErrorDescription {
            text += " · error \(lastErrorDescription)"
        }
        return text
    }
}

public struct MediaProcessorChainSummary {
    public let processorTypeNames: [String]
    public let sinkTypeNames: [String]

    public var summaryText: String {
        "processors \(processorTypeNames.count) · sinks \(sinkTypeNames.count)"
    }
}
