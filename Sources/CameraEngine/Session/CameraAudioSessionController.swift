//
//  CameraAudioSessionController.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public final class CameraAudioSessionController {
    public enum Event: Equatable {
        case didActivate
        case didDeactivate
        case routeChanged(String)
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case activationFailed(String)
    }

    public var eventHandler: ((Event) -> Void)?
    public var isActive: Bool { leases.contains(token) }
    private let token = UUID()
    private let leases: CameraAudioLeaseCoordinator
    private let eventQueue = DispatchQueue(label: "com.condy.kakapos.camera-audio.events")
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var values: [ObjectIdentifier: CameraAudioLeaseCoordinator] = [:]
    }
    private static let registry = Registry()

    private let audioSession: AVAudioSession
    private var observers: [NSObjectProtocol] = []
    private let eventDispatcher = CameraEventDispatcher<Event>()

    private final class NativeBackend {
        private let session: AVAudioSession
        private var before: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
        private var applied: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
        init(_ session: AVAudioSession) { self.session = session }
        func activate(_ mixes: Bool) throws {
            let prior = before; let priorApplied = applied
            let current = (session.category, session.mode, session.categoryOptions)
            if before == nil { before = current }
            let options: AVAudioSession.CategoryOptions = mixes ? [.mixWithOthers] : [.defaultToSpeaker]
            do {
                try session.setCategory(.playAndRecord, mode: .videoRecording, options: options)
                try session.setActive(true)
                applied = (session.category, session.mode, session.categoryOptions)
            } catch {
                try? session.setCategory(current.0, mode: current.1, options: current.2)
                before = prior; applied = priorApplied
                throw error
            }
        }
        func deactivate() throws {
            guard let applied, session.category == applied.0, session.mode == applied.1, session.categoryOptions == applied.2 else {
                // 宿主已主动改写策略，不能再覆盖宿主的会话。
                before = nil; self.applied = nil; return
            }
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
        func restore() throws {
            defer { before = nil; applied = nil }
            if let before, let applied, session.category == applied.0, session.mode == applied.1, session.categoryOptions == applied.2 {
                try session.setCategory(before.0, mode: before.1, options: before.2)
            }
        }
    }

    public init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        let registry = Self.registry
        registry.lock.lock()
        let identity = ObjectIdentifier(audioSession)
        if let existing = registry.values[identity] { leases = existing }
        else {
            let backend = NativeBackend(audioSession)
            let value = CameraAudioLeaseCoordinator(activate: backend.activate, deactivate: backend.deactivate, restore: backend.restore)
            registry.values[identity] = value; leases = value
        }
        registry.lock.unlock()
        startObserving()
    }

    init(coordinator: CameraAudioLeaseCoordinator) {
        audioSession = .sharedInstance()
        leases = coordinator
    }

    @discardableResult
    public func addEventObserver(_ handler: @escaping (Event) -> Void) -> UUID {
        eventDispatcher.addObserver(handler)
    }

    public func removeEventObserver(_ token: UUID) {
        eventDispatcher.removeObserver(token)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        try? leases.release(token, abandoning: true)
    }

    public func activate(prefersIndependentSession: Bool) { _ = try? activateForRun(prefersIndependentSession: prefersIndependentSession) }
    @discardableResult func activateForRun(prefersIndependentSession: Bool) throws -> Bool {
        do {
            let acquired = try leases.acquire(token, mixes: prefersIndependentSession)
            if acquired { emit(.didActivate) }
            return acquired
        } catch { emit(.activationFailed(error.localizedDescription)); throw error }
    }
    public func deactivate() {
        do { if try leases.release(token) { emit(.didDeactivate) } }
        catch { emit(.activationFailed(error.localizedDescription)) }
    }

    private func startObserving() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: audioSession, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.leases.interrupted()
            do { try self.leases.resumeIfNeeded() } catch { self.emit(.activationFailed(error.localizedDescription)) }
        })
        observers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: audioSession, queue: nil) { [weak self] notification in
                let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                self?.emit(.routeChanged(String(describing: reason)))
            }
        )
        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: audioSession, queue: nil) { [weak self] notification in
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                switch type {
                case .began:
                    self?.leases.interrupted()
                    self?.emit(.interruptionBegan)
                case .ended:
                    let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    let resumes = options.contains(.shouldResume)
                    if resumes {
                        do { try self?.leases.resumeIfNeeded() }
                        catch { self?.emit(.activationFailed(error.localizedDescription)) }
                    }
                    self?.emit(.interruptionEnded(shouldResume: resumes))
                default:
                    break
                }
            }
        )
    }

    private func emit(_ event: Event) {
        eventQueue.async {
            self.eventHandler?(event)
            self.eventDispatcher.emit(event)
        }
    }
}
#endif
