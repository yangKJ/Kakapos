// 作者：Condy
import Foundation

/// 处理结果先暂存，由原生最终回调或超时决定唯一终态。
final class CameraPhotoRequestResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var staged: Result<Value, Error>?
    private var completed = false

    func stage(_ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        if case .failure? = staged { return }
        staged = result
    }

    func finish(error: Error? = nil) -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return nil }
        completed = true
        defer { staged = nil }
        if let error { return .failure(error) }
        return staged ?? .failure(CameraPhotoCaptureError.missingResource)
    }
}

/// Task 取消立即结束调用方等待；原生请求的后续清理由捕获 owner 执行。
final class CameraPhotoTask<Value: Sendable>: @unchecked Sendable {
    let resourceID = UUID()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancelAction: (() -> Void)?
    private var completed = false
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func begin(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func onCancel(_ action: @escaping () -> Void) {
        lock.lock()
        let shouldCancel = cancelled
        if !completed { cancelAction = action }
        lock.unlock()
        if shouldCancel { action() }
    }

    @discardableResult
    func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard !completed else { lock.unlock(); return false }
        completed = true
        let continuation = continuation
        self.continuation = nil
        cancelAction = nil
        lock.unlock()
        continuation?.resume(with: result)
        return true
    }

    func cancel() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        cancelled = true
        let continuation = continuation
        let action = cancelAction
        self.continuation = nil
        cancelAction = nil
        lock.unlock()
        action?()
        continuation?.resume(throwing: CancellationError())
    }
}
