//
//  CameraSessionLifecycle.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public enum CameraPosition: String, Equatable, Sendable, Codable, CustomStringConvertible {
    case front
    case back
    case unspecified

    public var description: String {
        rawValue
    }
}

public enum CameraSessionState: Equatable {
    case idle
    case starting
    case running
    case paused
    case interrupted
    case switchingPosition
    case unauthorized
    case error
    case stopped
}

public enum CameraSessionEvent: Equatable {
    case willStart
    case didStart
    case didPause
    case didResume
    case didStop
    case wasInterrupted
    case interruptionEnded
    case willSwitchPosition(CameraPosition)
    case runtimeError(isRecoverable: Bool, description: String?)
    case positionChanged(CameraPosition)
    case authorizationChanged(CameraAuthorizationStatus)
}

enum CameraLifecycleAction: Equatable {
    case startRequested
    case pauseRequested
    case resumeRequested
    case didStartRunning
    case didStopRunning
    case wasInterrupted
    case interruptionEnded
    case positionSwitchRequested(CameraPosition)
    case runtimeError(isRecoverable: Bool, description: String?)
    case positionChanged(CameraPosition)
    case authorizationChanged(CameraAuthorizationStatus)
}

struct CameraSessionLifecycle {
    private(set) var state: CameraSessionState
    private(set) var position: CameraPosition
    private(set) var shouldAttemptRecovery: Bool
    private(set) var authorizationStatus: CameraAuthorizationStatus
    private var stateBeforeInterruption: CameraSessionState?

    init(position: CameraPosition, authorizationStatus: CameraAuthorizationStatus = .authorized) {
        self.state = .idle
        self.position = position
        self.shouldAttemptRecovery = false
        self.authorizationStatus = authorizationStatus
        if authorizationStatus == .denied {
            self.state = .unauthorized
        }
    }

    @discardableResult
    mutating func handle(_ action: CameraLifecycleAction) -> CameraSessionEvent? {
        switch action {
        case .startRequested:
            guard authorizationStatus == .authorized else {
                state = .unauthorized
                shouldAttemptRecovery = false
                return .authorizationChanged(authorizationStatus)
            }
            state = .starting
            shouldAttemptRecovery = false
            return .willStart
        case .pauseRequested:
            guard state == .running else { return nil }
            state = .paused
            return .didPause
        case .resumeRequested:
            guard state == .paused else { return nil }
            state = .running
            return .didResume
        case .didStartRunning:
            state = .running
            shouldAttemptRecovery = false
            return .didStart
        case .didStopRunning:
            state = .stopped
            stateBeforeInterruption = nil
            shouldAttemptRecovery = false
            return .didStop
        case .wasInterrupted:
            stateBeforeInterruption = state
            state = .interrupted
            return .wasInterrupted
        case .interruptionEnded:
            state = stateBeforeInterruption == .paused ? .paused : .running
            stateBeforeInterruption = nil
            return .interruptionEnded
        case .positionSwitchRequested(let position):
            state = .switchingPosition
            self.position = position
            return .willSwitchPosition(position)
        case .runtimeError(let isRecoverable, let description):
            state = .error
            shouldAttemptRecovery = isRecoverable
            return .runtimeError(isRecoverable: isRecoverable, description: description)
        case .positionChanged(let position):
            self.position = position
            if state == .switchingPosition {
                state = .running
            }
            return .positionChanged(position)
        case .authorizationChanged(let status):
            authorizationStatus = status
            if status == .authorized {
                if state == .unauthorized {
                    state = .idle
                }
            } else {
                state = .unauthorized
                shouldAttemptRecovery = false
            }
            return .authorizationChanged(status)
        }
    }
}
