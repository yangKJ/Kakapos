//
//  CameraZoomRequestGate.swift
//  KakaposCamera
//
//  Created by Condy on 2026/11/9.
//

import Foundation

/// 请求在入队时取得版本，停止立即撤销排队的旧请求。
final class CameraZoomRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var enabled = true
    private var discarded = 0

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    var discardedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return discarded
    }

    func issue() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return nil }
        revision &+= 1
        return revision
    }

    func setEnabled(_ value: Bool) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        enabled = value
        revision &+= 1
        return revision
    }

    func accepts(_ value: UInt64, requiresEnabled: Bool = true) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let accepted = revision == value && (!requiresEnabled || enabled)
        if !accepted { discarded += 1 }
        return accepted
    }
}
