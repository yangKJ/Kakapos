// 作者：Condy
import Foundation
import AVFoundation

/// 同一捕获会话只有一个串行执行域；只有最后一个分支释放后才停止本层启动的会话。
final class CameraSessionOwner: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.condy.kakapos.camera-session.owner")
    private let key = DispatchSpecificKey<UInt8>()
    private let isRunning: () -> Bool
    private let startNative: () -> Void
    private let stopNative: () -> Void
    private var active: Set<UUID> = []
    private var startedByOwner = false
    private var batchDepth = 0

    init(isRunning: @escaping () -> Bool, start: @escaping () -> Void, stop: @escaping () -> Void) {
        self.isRunning = isRunning; startNative = start; stopNative = stop
        queue.setSpecific(key: key, value: 1)
    }
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) != nil { return try body() }
        return try queue.sync(execute: body)
    }
    func start(_ branch: UUID) {
        sync { active.insert(branch); startIfNeeded() }
    }
    func stop(_ branch: UUID, willStop: () -> Void = {}) {
        sync {
            active.remove(branch)
            guard active.isEmpty, startedByOwner else { return }
            startedByOwner = false
            if isRunning() { willStop(); stopNative() }
        }
    }
    func batch(_ body: () -> Void) {
        sync {
            batchDepth += 1
            body()
            batchDepth -= 1
            startIfNeeded()
        }
    }
    private func startIfNeeded() {
        guard batchDepth == 0, !active.isEmpty, !isRunning() else { return }
        startedByOwner = true
        startNative()
    }
    private final class WeakOwner { weak var value: CameraSessionOwner?; init(_ value: CameraSessionOwner) { self.value = value } }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var entries: [ObjectIdentifier: WeakOwner] = [:]
    }
    private static let registry = Registry()
    static func shared(for session: AVCaptureSession) -> CameraSessionOwner {
        registry.lock.lock(); defer { registry.lock.unlock() }
        registry.entries = registry.entries.filter { $0.value.value != nil }
        let identity = ObjectIdentifier(session)
        if let owner = registry.entries[identity]?.value { return owner }
        let owner = CameraSessionOwner(isRunning: { session.isRunning }, start: { session.startRunning() }, stop: { session.stopRunning() })
        registry.entries[identity] = WeakOwner(owner)
        return owner
    }
}
