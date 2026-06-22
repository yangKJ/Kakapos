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
    public private(set) var isActive = false

    private let audioSession: AVAudioSession
    private var observers: [NSObjectProtocol] = []
    private let eventDispatcher = CameraEventDispatcher<Event>()

    public init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        startObserving()
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
    }

    public func activate(prefersIndependentSession: Bool) {
        do {
            let options: AVAudioSession.CategoryOptions = prefersIndependentSession ? [.mixWithOthers] : [.defaultToSpeaker]
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: options)
            try audioSession.setActive(true)
            isActive = true
            emit(.didActivate)
        } catch {
            emit(.activationFailed(error.localizedDescription))
        }
    }

    public func deactivate() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            emit(.activationFailed(error.localizedDescription))
            return
        }
        isActive = false
        emit(.didDeactivate)
    }

    private func startObserving() {
        let center = NotificationCenter.default
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
                    self?.emit(.interruptionBegan)
                case .ended:
                    let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    self?.emit(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                default:
                    break
                }
            }
        )
    }

    private func emit(_ event: Event) {
        eventHandler?(event)
        eventDispatcher.emit(event)
    }
}
#endif
