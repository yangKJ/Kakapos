//
//  CameraFrameIngressGate.swift
//  Kakapos
//
//  Created by Condy on 2026/8/10.
//

import Foundation

public struct CameraFrameIngressSnapshot: Equatable, Sendable {
    public let maximumInFlightFrameCount: Int
    public let inFlightFrameCount: Int
    public let highWaterMark: Int
    public let droppedVideoFrameCount: Int
    public let droppedAudioFrameCount: Int

    public var droppedFrameCount: Int {
        droppedVideoFrameCount + droppedAudioFrameCount
    }
}

enum CameraFrameIngressMediaKind {
    case video
    case audio
}

final class CameraFrameIngressGate {
    struct Token: Hashable {
        let generation: UInt64
        let identifier: UInt64
    }

    private let lock = NSLock()
    private let maximumInFlightFrameCount: Int
    private var acceptingFrames = false
    private var generation: UInt64 = 0
    private var nextIdentifier: UInt64 = 0
    private var remainingBranchesByToken: [Token: Int] = [:]
    private var highWaterMark = 0
    private var droppedVideoFrameCount = 0
    private var droppedAudioFrameCount = 0

    init(maximumInFlightFrameCount: Int) {
        self.maximumInFlightFrameCount = max(1, maximumInFlightFrameCount)
    }

    var snapshot: CameraFrameIngressSnapshot {
        lock.lock()
        let snapshot = CameraFrameIngressSnapshot(
            maximumInFlightFrameCount: maximumInFlightFrameCount,
            inFlightFrameCount: remainingBranchesByToken.count,
            highWaterMark: highWaterMark,
            droppedVideoFrameCount: droppedVideoFrameCount,
            droppedAudioFrameCount: droppedAudioFrameCount
        )
        lock.unlock()
        return snapshot
    }

    @discardableResult
    func reset() -> UInt64 {
        lock.lock()
        generation &+= 1
        acceptingFrames = true
        remainingBranchesByToken.removeAll(keepingCapacity: true)
        highWaterMark = 0
        droppedVideoFrameCount = 0
        droppedAudioFrameCount = 0
        let generation = generation
        lock.unlock()
        return generation
    }

    @discardableResult
    func rejectFurtherFrames() -> UInt64 {
        lock.lock()
        generation &+= 1
        acceptingFrames = false
        remainingBranchesByToken.removeAll(keepingCapacity: true)
        let generation = generation
        lock.unlock()
        return generation
    }

    func admit(mediaKind: CameraFrameIngressMediaKind, branchCount: Int) -> Token? {
        lock.lock()
        guard acceptingFrames, remainingBranchesByToken.count < maximumInFlightFrameCount else {
            switch mediaKind {
            case .video:
                droppedVideoFrameCount += 1
            case .audio:
                droppedAudioFrameCount += 1
            }
            lock.unlock()
            return nil
        }
        nextIdentifier &+= 1
        let token = Token(generation: generation, identifier: nextIdentifier)
        remainingBranchesByToken[token] = max(1, branchCount)
        highWaterMark = max(highWaterMark, remainingBranchesByToken.count)
        lock.unlock()
        return token
    }

    func isActive(_ token: Token) -> Bool {
        lock.lock()
        let isActive = acceptingFrames
            && token.generation == generation
            && remainingBranchesByToken[token] != nil
        lock.unlock()
        return isActive
    }

    func isCurrentGeneration(_ expectedGeneration: UInt64) -> Bool {
        lock.lock()
        let isCurrent = expectedGeneration == generation
        lock.unlock()
        return isCurrent
    }

    func completeBranch(for token: Token) {
        lock.lock()
        guard token.generation == generation,
              let remainingBranches = remainingBranchesByToken[token] else {
            lock.unlock()
            return
        }
        if remainingBranches > 1 {
            remainingBranchesByToken[token] = remainingBranches - 1
        } else {
            remainingBranchesByToken[token] = nil
        }
        lock.unlock()
    }
}
