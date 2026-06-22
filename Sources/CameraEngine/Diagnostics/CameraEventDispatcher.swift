//
//  CameraEventDispatcher.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

final class CameraEventDispatcher<Event> {
    typealias Handler = (Event) -> Void

    private var observers: [UUID: Handler] = [:]
    private let lock = NSLock()

    @discardableResult
    func addObserver(_ handler: @escaping Handler) -> UUID {
        let token = UUID()
        lock.lock()
        observers[token] = handler
        lock.unlock()
        return token
    }

    func removeObserver(_ token: UUID) {
        lock.lock()
        observers[token] = nil
        lock.unlock()
    }

    func emit(_ event: Event) {
        lock.lock()
        let handlers = Array(observers.values)
        lock.unlock()
        handlers.forEach { $0(event) }
    }
}
