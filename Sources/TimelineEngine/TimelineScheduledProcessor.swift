// 作者：Condy
import Foundation
import AVFoundation
import KakaposMediaCore

/// 时间线默认处理入口只经过当前活动效果；每个任务持有其处理器实例和共享混合资源。
final class TimelineScheduledProcessor: CancellableFrameProcessor, FrameProcessorCapabilityProviding, @unchecked Sendable {
    private struct Interval {
        let range: CMTimeRange
        let indices: [Int]
    }
    private final class Work: FrameProcessingOperation, @unchecked Sendable {
        let lock = NSLock()
        let processors: [FrameProcessor]
        let completion: (Result<MediaFrame, Error>) -> Void
        var operation: FrameProcessingOperation?
        var token: UInt64 = 0
        var completed = false
        var lifetime: Work?
        init(processors: [FrameProcessor], completion: @escaping (Result<MediaFrame, Error>) -> Void) {
            self.processors = processors; self.completion = completion
            lifetime = self
        }
        var active: Bool { lock.lock(); defer { lock.unlock() }; return !completed }
        func finish(_ result: Result<MediaFrame, Error>) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            let operation = self.operation
            self.operation = nil
            lock.unlock()
            if case .failure = result { operation?.cancel() }
            completion(result)
            lock.lock(); lifetime = nil; lock.unlock()
        }
        func cancel() { finish(.failure(MediaCoreError.processingCancelled)) }
    }

    let capabilities: FrameProcessorCapabilities
    private let processors: [FrameProcessor]
    private let intervals: [Interval]
    private let queue = DispatchQueue(label: "com.condy.kakapos.timeline-effects", qos: .userInitiated)

    init?(plan: TimelineRenderPlan) {
        let resources = TimelineEffectResources()
        var indices: [UUID: Int] = [:]
        var processors: [FrameProcessor] = []
        for segment in plan.processorSegments.sorted(by: { $0.layerLevel < $1.layerLevel }) {
            guard let processor = segment.source.makeProcessor() else { continue }
            indices[segment.identity] = processors.count
            processors.append(TimelineEffectProcessor(segment: segment, processor: processor, resources: resources))
        }
        guard !processors.isEmpty else { return nil }
        self.processors = processors
        self.intervals = plan.visualIntervals.map { interval in
            Interval(range: interval.timeRange, indices: interval.processorSegments.compactMap { indices[$0.identity] }.sorted())
        }.sorted { $0.range.start < $1.range.start }
        var ranges: Set<FrameDynamicRange> = [.standard, .hdr(.hlg), .hdr(.pq)]
        var preserves = true
        for processor in processors {
            let value = (processor as! FrameProcessorCapabilityProviding).capabilities
            ranges.formIntersection(value.supportedDynamicRanges.isEmpty ? [.standard] : value.supportedDynamicRanges)
            preserves = preserves && value.preservesColorInformation
        }
        capabilities = FrameProcessorCapabilities(supportedDynamicRanges: ranges.isEmpty ? [.unknown] : ranges,
            preservesColorInformation: preserves, maximumConcurrentFrameCount: 1)
    }

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        _ = processCancellable(frame, completion: completion)
    }

    func processCancellable(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) -> FrameProcessingOperation {
        let time = frame.metadata.presentationTime
        var low = 0
        var high = intervals.count
        while low < high {
            let middle = (low + high) / 2
            if intervals[middle].range.start <= time { low = middle + 1 } else { high = middle }
        }
        let indices = low > 0 && CMTimeRangeContainsTime(intervals[low - 1].range, time: time) ? intervals[low - 1].indices : []
        let work = Work(processors: indices.map { processors[$0] }, completion: completion)
        queue.async { self.process(frame, at: 0, work: work) }
        return work
    }

    private func process(_ frame: MediaFrame, at index: Int, work: Work) {
        guard work.active else { return }
        guard index < work.processors.count else { work.finish(.success(frame)); return }
        work.lock.lock(); work.token &+= 1; let token = work.token; work.operation = nil; work.lock.unlock()
        let operation = processFrame(using: work.processors[index], frame: frame) { result in
            guard work.active else { return }
            work.lock.lock(); work.token &+= 1; work.operation = nil; work.lock.unlock()
            switch result {
            case .success(let value): self.queue.async { self.process(value, at: index + 1, work: work) }
            case .failure(let error): work.finish(.failure(error))
            }
        }
        work.lock.lock()
        let cancelled = work.completed
        if !cancelled && work.token == token { work.operation = operation }
        work.lock.unlock()
        if cancelled { operation?.cancel() }
    }
}
