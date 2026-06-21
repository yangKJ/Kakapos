//
//  MediaPipelineSummary.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

public struct MediaPipelineSummary {
    public let sourceTypeName: String
    public let processorTypeNames: [String]
    public let sinkTypeNames: [String]
    public let state: MediaPipeline.State

    public var summaryText: String {
        "source \(sourceTypeName) · processors \(processorTypeNames.count) · sinks \(sinkTypeNames.count) · state \(state)"
    }
}

public struct MediaProcessorChainSummary {
    public let processorTypeNames: [String]
    public let sinkTypeNames: [String]

    public var summaryText: String {
        "processors \(processorTypeNames.count) · sinks \(sinkTypeNames.count)"
    }
}

