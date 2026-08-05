//
//  VideoPreviewMode.swift
//  Kakapos
//
//  Created by Condy on 2026/8/5.
//

import AVFoundation

public struct VideoPreviewGeneration: Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public enum VideoPreviewMode: @unchecked Sendable {
    case original
    case processed(FrameProcessingPlan)

    public var identity: VideoPreviewModeIdentity {
        switch self {
        case .original:
            return .original
        case let .processed(plan):
            return .processed(plan.identity)
        }
    }
}

public enum VideoPreviewModeIdentity: Hashable, Sendable {
    case original
    case processed(FrameProcessingPlan.Identity)
}

public enum VideoPreviewReadiness: Sendable {
    case idle
    case awaitingFirstFrame(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    )
    case ready(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity,
        presentationTime: CMTime
    )
    case failed(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    )
    case cancelled
}

public struct VideoPreviewConfiguration: Sendable {
    public let preferredFramesPerSecond: Int

    public init(preferredFramesPerSecond: Int = 30) {
        self.preferredFramesPerSecond = min(max(preferredFramesPerSecond, 1), 60)
    }
}
