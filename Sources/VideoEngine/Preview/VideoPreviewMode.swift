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
    public let adaptivePolicy: VideoPreviewAdaptivePolicy?

    public init(
        preferredFramesPerSecond: Int = 30,
        adaptivePolicy: VideoPreviewAdaptivePolicy? = nil
    ) {
        self.preferredFramesPerSecond = min(max(preferredFramesPerSecond, 1), 60)
        self.adaptivePolicy = adaptivePolicy
    }
}

public struct VideoPreviewAdaptivePolicy: Equatable, Sendable {
    public let minimumFramesPerSecond: Int
    public let maximumFramesPerSecond: Int
    public let overloadBudgetRatio: Double
    public let recoverySampleCount: Int

    public init(
        minimumFramesPerSecond: Int = 15,
        maximumFramesPerSecond: Int = 30,
        overloadBudgetRatio: Double = 0.9,
        recoverySampleCount: Int = 24
    ) {
        let minimum = min(max(minimumFramesPerSecond, 1), 60)
        self.minimumFramesPerSecond = minimum
        self.maximumFramesPerSecond = min(max(maximumFramesPerSecond, minimum), 60)
        self.overloadBudgetRatio = min(max(overloadBudgetRatio, 0.25), 1)
        self.recoverySampleCount = max(recoverySampleCount, 1)
    }

    public func recommendation(
        currentFramesPerSecond: Int,
        processingDuration: TimeInterval,
        consecutiveUnderBudgetSamples: Int
    ) -> Int {
        let current = min(max(currentFramesPerSecond, minimumFramesPerSecond), maximumFramesPerSecond)
        let frameBudget = 1 / Double(max(current, 1))
        if processingDuration > frameBudget * overloadBudgetRatio {
            return max(minimumFramesPerSecond, current - 5)
        }
        guard consecutiveUnderBudgetSamples >= recoverySampleCount else { return current }
        return min(maximumFramesPerSecond, current + 5)
    }
}
