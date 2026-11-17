// 作者：Condy
import Foundation

/// 一个控制器持有一个租约；全局音频仅在首个租约时激活，在最后一个租约释放时停用。
final class CameraAudioLeaseCoordinator: @unchecked Sendable {
    enum LeaseError: LocalizedError {
        case incompatibleConfiguration
        var errorDescription: String? { "共享音频会话已有不同的混音策略，请统一配置或由宿主管理。" }
    }
    private let queue = DispatchQueue(label: "com.condy.kakapos.camera-audio.leases")
    private let key = DispatchSpecificKey<UInt8>()
    private var leases: [UUID: Bool] = [:]
    private let activate: (Bool) throws -> Void
    private let deactivate: () throws -> Void
    private let restore: () throws -> Void
    private var backendActive = false
    init(activate: @escaping (Bool) throws -> Void, deactivate: @escaping () throws -> Void, restore: @escaping () throws -> Void = {}) {
        self.activate = activate; self.deactivate = deactivate; self.restore = restore
        queue.setSpecific(key: key, value: 1)
    }
    private func sync<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) != nil { return try body() }
        return try queue.sync(execute: body)
    }
    func contains(_ token: UUID) -> Bool { sync { leases[token] != nil } }
    @discardableResult func acquire(_ token: UUID, mixes: Bool) throws -> Bool {
        try sync {
            guard leases[token] == nil else { return false }
            if let existing = leases.values.first, existing != mixes { throw LeaseError.incompatibleConfiguration }
            if leases.isEmpty || !backendActive { try activate(mixes); backendActive = true }
            leases[token] = mixes
            return true
        }
    }
    func interrupted() { sync { backendActive = false } }
    func resumeIfNeeded() throws {
        try sync {
            guard !backendActive, let mixes = leases.values.first else { return }
            try activate(mixes); backendActive = true
        }
    }
    @discardableResult func release(_ token: UUID, abandoning: Bool = false) throws -> Bool {
        try sync {
            guard leases[token] != nil else { return false }
            let last = leases.count == 1
            do { if last && backendActive { try deactivate(); backendActive = false } }
            catch { if abandoning { leases[token] = nil }; throw error }
            leases[token] = nil
            if last { try restore() }
            return true
        }
    }
}
