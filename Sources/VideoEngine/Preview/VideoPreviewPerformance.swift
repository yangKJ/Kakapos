//
//  VideoPreviewPerformance.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import Foundation

public struct VideoPreviewPerformanceSnapshot: Equatable, Sendable {
    public let submittedFrameCount: Int
    public let startedFrameCount: Int
    public let completedFrameCount: Int
    public let failedFrameCount: Int
    public let cancelledFrameCount: Int
    public let coalescedFrameCount: Int
    public let averageProcessingDuration: TimeInterval
    public let maximumProcessingDuration: TimeInterval
    public let peakPendingFrameCount: Int
    public let lastFrameIndex: Int64?
    public let isFinal: Bool

    public var completionRatio: Double {
        guard submittedFrameCount > 0 else { return 0 }
        return Double(completedFrameCount) / Double(submittedFrameCount)
    }
}

final class VideoPreviewPerformanceAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var submittedFrameCount = 0
    private var startedFrameCount = 0
    private var completedFrameCount = 0
    private var failedFrameCount = 0
    private var cancelledFrameCount = 0
    private var coalescedFrameCount = 0
    private var totalProcessingDuration: TimeInterval = 0
    private var maximumProcessingDuration: TimeInterval = 0
    private var peakPendingFrameCount = 0
    private var lastFrameIndex: Int64?
    private var isFinal = false

    var snapshot: VideoPreviewPerformanceSnapshot {
        lock.withLock {
            VideoPreviewPerformanceSnapshot(
                submittedFrameCount: submittedFrameCount,
                startedFrameCount: startedFrameCount,
                completedFrameCount: completedFrameCount,
                failedFrameCount: failedFrameCount,
                cancelledFrameCount: cancelledFrameCount,
                coalescedFrameCount: coalescedFrameCount,
                averageProcessingDuration: completedFrameCount > 0 ? totalProcessingDuration / Double(completedFrameCount) : 0,
                maximumProcessingDuration: maximumProcessingDuration,
                peakPendingFrameCount: peakPendingFrameCount,
                lastFrameIndex: lastFrameIndex,
                isFinal: isFinal
            )
        }
    }

    func recordSubmitted(frameIndex: Int64?, isPending: Bool, replacesPending: Bool) {
        lock.withLock {
            guard !isFinal else { return }
            submittedFrameCount += 1
            lastFrameIndex = frameIndex
            if replacesPending { coalescedFrameCount += 1 }
            if isPending { peakPendingFrameCount = max(peakPendingFrameCount, 1) }
        }
    }

    func recordStarted() {
        lock.withLock {
            guard !isFinal else { return }
            startedFrameCount += 1
        }
    }

    func recordCompleted(duration: TimeInterval) {
        lock.withLock {
            guard !isFinal else { return }
            completedFrameCount += 1
            totalProcessingDuration += max(duration, 0)
            maximumProcessingDuration = max(maximumProcessingDuration, duration)
        }
    }

    func recordFailure() {
        lock.withLock {
            guard !isFinal else { return }
            failedFrameCount += 1
        }
    }

    func markFinal(hadInFlightFrame: Bool) {
        lock.withLock {
            guard !isFinal else { return }
            if hadInFlightFrame { cancelledFrameCount += 1 }
            isFinal = true
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
