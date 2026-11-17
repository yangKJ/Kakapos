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
    case interruptedWhileRecording
    case switchingPosition
    case reconfiguring
    case recovering
    case runtimePressureLimited
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
    case wasInterruptedWhileRecording
    case interruptionEnded
    case willSwitchPosition(CameraPosition)
    case runtimeError(isRecoverable: Bool, description: String?)
    case systemPressureChanged(String)
    case audioRouteChanged(String)
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
    case wasInterruptedWhileRecording
    case interruptionEnded
    case positionSwitchRequested(CameraPosition)
    case runtimeError(isRecoverable: Bool, description: String?)
    case systemPressureChanged(String)
    case audioRouteChanged(String)
    case positionChanged(CameraPosition)
    case authorizationChanged(CameraAuthorizationStatus)
}

struct CameraSessionLifecycle {
    private(set) var state: CameraSessionState
    private(set) var position: CameraPosition
    private(set) var shouldAttemptRecovery: Bool
    private(set) var authorizationStatus: CameraAuthorizationStatus
    private var stateBeforeInterruption: CameraSessionState?
    private var stateBeforePositionSwitch: CameraSessionState?

    init(position: CameraPosition, authorizationStatus: CameraAuthorizationStatus = .authorized) {
        self.state = .idle
        self.position = position
        self.shouldAttemptRecovery = false
        self.authorizationStatus = authorizationStatus
        if authorizationStatus == .denied {
            self.state = .unauthorized
        }
    }

    var canBeginInterruption: Bool {
        switch state {
        case .starting, .running, .paused, .reconfiguring, .switchingPosition, .recovering, .runtimePressureLimited:
            return true
        default: return false
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
            stateBeforePositionSwitch = nil
            shouldAttemptRecovery = false
            return .didStop
        case .wasInterrupted:
            guard canBeginInterruption else { return nil }
            stateBeforeInterruption = state
            state = .interrupted
            return .wasInterrupted
        case .wasInterruptedWhileRecording:
            guard canBeginInterruption else { return nil }
            stateBeforeInterruption = state
            state = .interruptedWhileRecording
            return .wasInterruptedWhileRecording
        case .interruptionEnded:
            guard state == .interrupted || state == .interruptedWhileRecording else { return nil }
            state = stateBeforeInterruption == .paused ? .paused : .running
            stateBeforeInterruption = nil
            return .interruptionEnded
        case .positionSwitchRequested(let position):
            if stateBeforePositionSwitch == nil { stateBeforePositionSwitch = state }
            state = .reconfiguring
            self.position = position
            return .willSwitchPosition(position)
        case .runtimeError(let isRecoverable, let description):
            if !isRecoverable { stateBeforePositionSwitch = nil }
            state = isRecoverable ? .recovering : .error
            shouldAttemptRecovery = isRecoverable
            return .runtimeError(isRecoverable: isRecoverable, description: description)
        case .systemPressureChanged(let level):
            if state == .running || state == .runtimePressureLimited { state = .runtimePressureLimited }
            return .systemPressureChanged(level)
        case .audioRouteChanged(let route):
            return .audioRouteChanged(route)
        case .positionChanged(let position):
            self.position = position
            if state == .switchingPosition || state == .reconfiguring || state == .recovering {
                state = stateBeforePositionSwitch ?? .running
            }
            stateBeforePositionSwitch = nil
            return .positionChanged(position)
        case .authorizationChanged(let status):
            authorizationStatus = status
            if status == .authorized {
                if state == .unauthorized {
                    state = .idle
                }
            } else {
                state = .unauthorized
                stateBeforePositionSwitch = nil
                shouldAttemptRecovery = false
            }
            return .authorizationChanged(status)
        }
    }
}

/// 调用方持有runLock；不持锁调用系统启动/停止或交付回调。
struct CameraRunLifecycle {
    private(set) var activeGeneration: UInt64?
    private(set) var isStopping = false
    private(set) var restartRequested = false
    private var expectedStop: UInt64?
    private var callbackDelivered = false

    mutating func begin(makeGeneration: () -> UInt64) -> UInt64? {
        guard activeGeneration == nil, !isStopping else { return nil }
        callbackDelivered = false
        let generation = makeGeneration()
        activeGeneration = generation
        return generation
    }

    mutating func completeAuthorization(generation: UInt64) -> Bool {
        guard isCurrent(generation), !isStopping else { return false }
        activeGeneration = nil
        return true
    }

    func isCurrent(_ generation: UInt64) -> Bool { activeGeneration == generation }

    mutating func beginTerminal(makeGeneration: () -> UInt64) -> UInt64? {
        guard activeGeneration != nil, !isStopping else { return nil }
        activeGeneration = nil
        isStopping = true
        callbackDelivered = false
        return makeGeneration()
    }

    mutating func invalidate(makeGeneration: () -> UInt64) -> UInt64 {
        activeGeneration = nil
        return makeGeneration()
    }

    mutating func deferStartIfStopping() -> Bool {
        guard isStopping else { return false }
        restartRequested = true
        return true
    }

    mutating func expectStop(generation: UInt64) {
        if isStopping { expectedStop = generation }
    }

    mutating func consumeExpectedStop() -> (consumed: Bool, restart: Bool) {
        guard expectedStop != nil else { return (false, false) }
        expectedStop = nil
        return (true, completeIfReady())
    }

    mutating func markCallbackDelivered() -> Bool {
        callbackDelivered = true
        return completeIfReady()
    }

    private mutating func completeIfReady() -> Bool {
        guard isStopping, callbackDelivered, expectedStop == nil else { return false }
        isStopping = false
        let restart = restartRequested
        restartRequested = false
        return restart
    }
}

/// 硬件边界可注入；每个阶段都复验运行身份，失败不能收掉并发建立的新会话。
enum CameraSessionRecovery {
    static func run(isCurrent: () -> Bool, configure: () throws -> Void, restart: () throws -> Bool,
                    ready: () -> Void, failed: (Error) -> Void) {
        guard isCurrent() else { return }
        do {
            try configure()
            guard isCurrent(), try restart(), isCurrent() else { return }
            ready()
        } catch {
            if isCurrent() { failed(error) }
        }
    }
}
