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
    case error
    case stopped
}

public enum CameraSessionEvent: Equatable {
    case willStart
    case didStart
    case didStop
    case wasInterrupted
    case interruptionEnded
    case runtimeError(isRecoverable: Bool, description: String?)
    case positionChanged(CameraPosition)
}

enum CameraLifecycleAction: Equatable {
    case startRequested
    case didStartRunning
    case didStopRunning
    case wasInterrupted
    case interruptionEnded
    case runtimeError(isRecoverable: Bool, description: String?)
    case positionChanged(CameraPosition)
}

struct CameraSessionLifecycle {
    private(set) var state: CameraSessionState
    private(set) var position: CameraPosition
    private(set) var shouldAttemptRecovery: Bool

    init(position: CameraPosition) {
        self.state = .idle
        self.position = position
        self.shouldAttemptRecovery = false
    }

    @discardableResult
    mutating func handle(_ action: CameraLifecycleAction) -> CameraSessionEvent? {
        switch action {
        case .startRequested:
            state = .starting
            shouldAttemptRecovery = false
            return .willStart
        case .didStartRunning:
            state = .running
            shouldAttemptRecovery = false
            return .didStart
        case .didStopRunning:
            state = .stopped
            shouldAttemptRecovery = false
            return .didStop
        case .wasInterrupted:
            state = .interrupted
            return .wasInterrupted
        case .interruptionEnded:
            state = .running
            return .interruptionEnded
        case .runtimeError(let isRecoverable, let description):
            state = .error
            shouldAttemptRecovery = isRecoverable
            return .runtimeError(isRecoverable: isRecoverable, description: description)
        case .positionChanged(let position):
            self.position = position
            return .positionChanged(position)
        }
    }
}
