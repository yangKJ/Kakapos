//
//  CameraSessionLifecycle.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public enum CameraPosition: Equatable {
    case front
    case back
    case unspecified
}

public enum CameraSessionState: Equatable {
    case idle
    case starting
    case running
    case interrupted
    case stopped
}

public enum CameraSessionEvent: Equatable {
    case willStart
    case didStart
    case didStop
    case wasInterrupted
    case interruptionEnded
    case positionChanged(CameraPosition)
}

enum CameraLifecycleAction: Equatable {
    case startRequested
    case didStartRunning
    case didStopRunning
    case wasInterrupted
    case interruptionEnded
    case positionChanged(CameraPosition)
}

struct CameraSessionLifecycle {
    private(set) var state: CameraSessionState
    private(set) var position: CameraPosition

    init(position: CameraPosition) {
        self.state = .idle
        self.position = position
    }

    @discardableResult
    mutating func handle(_ action: CameraLifecycleAction) -> CameraSessionEvent? {
        switch action {
        case .startRequested:
            state = .starting
            return .willStart
        case .didStartRunning:
            state = .running
            return .didStart
        case .didStopRunning:
            state = .stopped
            return .didStop
        case .wasInterrupted:
            state = .interrupted
            return .wasInterrupted
        case .interruptionEnded:
            state = .running
            return .interruptionEnded
        case .positionChanged(let position):
            self.position = position
            return .positionChanged(position)
        }
    }
}
