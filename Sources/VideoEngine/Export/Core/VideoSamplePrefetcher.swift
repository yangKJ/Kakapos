// 作者：Condy
import AVFoundation
import Foundation

/// 单一读取队列拥有视频解码；容量包含已解码但尚未交给处理器的帧。
final class VideoSamplePrefetcher: @unchecked Sendable {
    enum Next { case sample(CMSampleBuffer), waiting, finished }
    private let condition = NSCondition()
    private let queue = DispatchQueue(label: "com.condy.kakapos.export.video-read-ahead", qos: .userInitiated)
    // Output 不独立拥有 Reader；阻塞读取退出前必须保持整个读取会话存活。
    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput
    private let capacity: Int
    private let available: @Sendable () -> Void
    private let pressure: @Sendable (Int) -> Void
    private var samples: [CMSampleBuffer] = []
    private var isPaused = false
    private var isCancelled = false
    private var isFinished = false

    init(
        reader: AVAssetReader,
        output: AVAssetReaderOutput,
        capacity: Int,
        pressure: @escaping @Sendable (Int) -> Void,
        available: @escaping @Sendable () -> Void
    ) {
        self.reader = reader
        self.output = output
        self.capacity = min(max(capacity, 1), 2)
        self.available = available
        self.pressure = pressure
    }

    func start() { queue.async { self.produce() } }

    func take() -> Next {
        condition.lock()
        defer { condition.unlock() }
        guard !samples.isEmpty else { return isFinished || isCancelled ? .finished : .waiting }
        let sample = samples.removeFirst()
        condition.signal()
        return .sample(sample)
    }

    func setPaused(_ paused: Bool) {
        condition.lock()
        isPaused = paused
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        guard !isCancelled else { condition.unlock(); return }
        isCancelled = true
        samples.removeAll()
        condition.broadcast()
        condition.unlock()
        // SDK 拆除必须排在同步读帧退出之后；调用方只发送取消意图，不阻塞等待。
        queue.async {
            if self.reader.status == .reading { self.reader.cancelReading() }
        }
    }

    private func produce() {
        while true {
            condition.lock()
            while !isCancelled && (isPaused || samples.count >= capacity) { condition.wait() }
            let cancelled = isCancelled
            condition.unlock()
            guard !cancelled else { return }
            let sample = withExtendedLifetime(reader) { output.copyNextSampleBuffer() }
            condition.lock()
            guard !isCancelled else { condition.unlock(); return }
            if let sample { samples.append(sample) } else { isFinished = true }
            let count = samples.count
            condition.unlock()
            pressure(count)
            available()
            if sample == nil { return }
        }
    }
}
