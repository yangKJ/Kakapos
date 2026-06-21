//
//  PlayerFrameCoordinator.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

enum PlayerFramePlaybackState: Equatable {
    case idle
    case running
    case paused
    case waitingForMediaData
    case finished
}

struct PlayerFrameCoordinator {
    private(set) var playbackState: PlayerFramePlaybackState = .idle
    private(set) var frameIndex: Int64 = 0
    private(set) var currentItemID: ObjectIdentifier?
    private(set) var generation: Int64 = 0

    mutating func start(with item: AnyObject?) -> Bool {
        playbackState = .running
        return updateCurrentItem(item)
    }

    mutating func pause() {
        guard playbackState == .running || playbackState == .waitingForMediaData else { return }
        playbackState = .paused
    }

    mutating func resume() {
        guard playbackState == .paused || playbackState == .waitingForMediaData || playbackState == .idle else { return }
        playbackState = .running
    }

    mutating func stop() {
        playbackState = .finished
    }

    mutating func updateCurrentItem(_ item: AnyObject?) -> Bool {
        let nextID = item.map(ObjectIdentifier.init)
        guard nextID != currentItemID else { return false }
        currentItemID = nextID
        frameIndex = 0
        generation += 1
        return true
    }

    mutating func beginWaitingForMediaData() -> Bool {
        guard playbackState == .running else { return false }
        playbackState = .waitingForMediaData
        return true
    }

    mutating func mediaDataWillChange() -> Bool {
        guard playbackState == .waitingForMediaData else { return false }
        playbackState = .running
        return true
    }

    mutating func markFrameOutput() -> Int64 {
        frameIndex += 1
        if playbackState == .waitingForMediaData {
            playbackState = .running
        }
        return frameIndex
    }

    var shouldDriveDisplayLink: Bool {
        playbackState == .running
    }
}
