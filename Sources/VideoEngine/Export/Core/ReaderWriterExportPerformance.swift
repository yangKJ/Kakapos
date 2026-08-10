//
//  ReaderWriterExportPerformance.swift
//  Kakapos
//
//  Created by Condy on 2026/8/10.
//

import Foundation

public extension ReaderWriterExportJob {
    /// 一组以秒为单位的累计耗时统计。
    struct DurationStatistics: Equatable, Sendable {
        public let count: Int
        public let total: TimeInterval
        public let maximum: TimeInterval

        public var average: TimeInterval {
            guard count > 0 else { return 0 }
            return total / Double(count)
        }
    }

    /// Reader/Writer 导出的低开销诊断快照。
    /// 导出期间可读取实时值；进入终态后冻结，不包含产物校验耗时。
    struct PerformanceSnapshot: Equatable, Sendable {
        public let videoSamplesRead: Int
        public let audioSamplesRead: Int
        public let videoSamplesWritten: Int
        public let audioSamplesWritten: Int
        /// 进入完整 processor chain 的视频帧数，不是 processor stage 调用次数。
        public let processorInvocationCount: Int
        public let processorCompletionCount: Int
        public let processorTimeoutCount: Int
        public let peakProcessorInFlightCount: Int
        public let peakPendingProcessedFrameCount: Int
        /// 至少观察到一次 writer not-ready 的已处理视频帧数，不按轮询次数重复累计。
        public let processedFrameWriterBackpressureCount: Int
        /// 每帧所有 processor stage 排队时间的总和统计。
        public let processorQueueDelay: DurationStatistics
        /// 每帧所有 processor stage 从开始执行到回调的总和统计，不等同于纯 GPU 时间。
        public let processorExecutionDuration: DurationStatistics
        /// 每帧从提交完整 chain 到最终 stage 回调的墙钟耗时统计。
        public let processorTotalDuration: DurationStatistics
        /// 最终 stage 回调到导出 owner queue 接收结果的耗时统计。
        public let processorOwnerDeliveryDelay: DurationStatistics
        public let processorEndToEndDuration: DurationStatistics
        public let processedFrameWriterWaitDuration: DurationStatistics
        public let sessionDuration: TimeInterval
        public let finishingDuration: TimeInterval
        public let isFinal: Bool
    }
}

final class ReaderWriterExportPerformanceAccumulator: @unchecked Sendable {
    typealias Clock = @Sendable () -> UInt64

    private struct DurationAccumulator {
        private(set) var count = 0
        private(set) var totalNanoseconds: UInt64 = 0
        private(set) var maximumNanoseconds: UInt64 = 0

        mutating func record(_ nanoseconds: UInt64) {
            count += 1
            let addition = totalNanoseconds.addingReportingOverflow(nanoseconds)
            totalNanoseconds = addition.overflow ? .max : addition.partialValue
            maximumNanoseconds = max(maximumNanoseconds, nanoseconds)
        }

        var snapshot: ReaderWriterExportJob.DurationStatistics {
            ReaderWriterExportJob.DurationStatistics(
                count: count,
                total: Self.seconds(from: totalNanoseconds),
                maximum: Self.seconds(from: maximumNanoseconds)
            )
        }

        private static func seconds(from nanoseconds: UInt64) -> TimeInterval {
            TimeInterval(nanoseconds) / 1_000_000_000
        }
    }

    private let lock = NSLock()
    private let clock: Clock
    private var startTime: UInt64?
    private var finishingStartTime: UInt64?
    private var finalTime: UInt64?
    private var isFinal = false
    private var videoSamplesRead = 0
    private var audioSamplesRead = 0
    private var videoSamplesWritten = 0
    private var audioSamplesWritten = 0
    private var processorInvocationCount = 0
    private var processorCompletionCount = 0
    private var processorTimeoutCount = 0
    private var processorInFlightCount = 0
    private var peakProcessorInFlightCount = 0
    private var pendingProcessedFrameCount = 0
    private var peakPendingProcessedFrameCount = 0
    private var pendingProcessedFrameStartTime: UInt64?
    private var pendingProcessedFrameObservedBackpressure = false
    private var processedFrameWriterBackpressureCount = 0
    private var processorQueueDelay = DurationAccumulator()
    private var processorExecutionDuration = DurationAccumulator()
    private var processorTotalDuration = DurationAccumulator()
    private var processorOwnerDeliveryDelay = DurationAccumulator()
    private var processorEndToEndDuration = DurationAccumulator()
    private var processedFrameWriterWaitDuration = DurationAccumulator()

    init(clock: @escaping Clock = { DispatchTime.now().uptimeNanoseconds }) {
        self.clock = clock
    }

    func now() -> UInt64 {
        clock()
    }

    func markStarted(at time: UInt64? = nil) {
        withLock {
            guard isFinal == false, startTime == nil else { return }
            startTime = time ?? clock()
        }
    }

    func recordVideoSampleRead() {
        withLock {
            guard isFinal == false else { return }
            videoSamplesRead += 1
        }
    }

    func recordAudioSampleRead() {
        withLock {
            guard isFinal == false else { return }
            audioSamplesRead += 1
        }
    }

    func recordVideoSampleWritten() {
        withLock {
            guard isFinal == false else { return }
            videoSamplesWritten += 1
        }
    }

    func recordAudioSampleWritten() {
        withLock {
            guard isFinal == false else { return }
            audioSamplesWritten += 1
        }
    }

    func recordProcessorSubmitted() {
        withLock {
            guard isFinal == false else { return }
            processorInvocationCount += 1
            processorInFlightCount += 1
            peakProcessorInFlightCount = max(peakProcessorInFlightCount, processorInFlightCount)
        }
    }

    func recordProcessorCompleted(
        submittedAt: UInt64,
        queueDelayNanoseconds: UInt64,
        executionDurationNanoseconds: UInt64,
        callbackCompletedAt: UInt64,
        ownerDeliveredAt: UInt64
    ) {
        withLock {
            guard isFinal == false else { return }
            processorCompletionCount += 1
            processorInFlightCount = max(processorInFlightCount - 1, 0)
            processorQueueDelay.record(queueDelayNanoseconds)
            processorExecutionDuration.record(executionDurationNanoseconds)
            processorTotalDuration.record(Self.elapsed(from: submittedAt, to: callbackCompletedAt))
            processorOwnerDeliveryDelay.record(Self.elapsed(from: callbackCompletedAt, to: ownerDeliveredAt))
            processorEndToEndDuration.record(Self.elapsed(from: submittedAt, to: ownerDeliveredAt))
        }
    }

    func recordProcessorTimedOut() {
        withLock {
            guard isFinal == false else { return }
            processorTimeoutCount += 1
            processorInFlightCount = max(processorInFlightCount - 1, 0)
        }
    }

    func recordPendingProcessedFrame(at time: UInt64? = nil) {
        withLock {
            guard isFinal == false else { return }
            pendingProcessedFrameCount = 1
            peakPendingProcessedFrameCount = max(peakPendingProcessedFrameCount, pendingProcessedFrameCount)
            pendingProcessedFrameStartTime = time ?? clock()
            pendingProcessedFrameObservedBackpressure = false
        }
    }

    func recordProcessedFrameWriterBackpressure() {
        withLock {
            guard isFinal == false,
                  pendingProcessedFrameCount == 1,
                  pendingProcessedFrameObservedBackpressure == false else { return }
            pendingProcessedFrameObservedBackpressure = true
            processedFrameWriterBackpressureCount += 1
        }
    }

    func recordPendingProcessedFrameWritten(at time: UInt64? = nil) {
        withLock {
            guard isFinal == false,
                  let pendingProcessedFrameStartTime else { return }
            processedFrameWriterWaitDuration.record(Self.elapsed(
                from: pendingProcessedFrameStartTime,
                to: time ?? clock()
            ))
            pendingProcessedFrameCount = 0
            self.pendingProcessedFrameStartTime = nil
            pendingProcessedFrameObservedBackpressure = false
        }
    }

    func markFinishing(at time: UInt64? = nil) {
        withLock {
            guard isFinal == false, finishingStartTime == nil else { return }
            finishingStartTime = time ?? clock()
        }
    }

    func markFinal(at time: UInt64? = nil) {
        withLock {
            guard isFinal == false else { return }
            finalTime = time ?? clock()
            processorInFlightCount = 0
            pendingProcessedFrameCount = 0
            pendingProcessedFrameStartTime = nil
            isFinal = true
        }
    }

    var snapshot: ReaderWriterExportJob.PerformanceSnapshot {
        withLock {
            let snapshotTime = finalTime ?? clock()
            return ReaderWriterExportJob.PerformanceSnapshot(
                videoSamplesRead: videoSamplesRead,
                audioSamplesRead: audioSamplesRead,
                videoSamplesWritten: videoSamplesWritten,
                audioSamplesWritten: audioSamplesWritten,
                processorInvocationCount: processorInvocationCount,
                processorCompletionCount: processorCompletionCount,
                processorTimeoutCount: processorTimeoutCount,
                peakProcessorInFlightCount: peakProcessorInFlightCount,
                peakPendingProcessedFrameCount: peakPendingProcessedFrameCount,
                processedFrameWriterBackpressureCount: processedFrameWriterBackpressureCount,
                processorQueueDelay: processorQueueDelay.snapshot,
                processorExecutionDuration: processorExecutionDuration.snapshot,
                processorTotalDuration: processorTotalDuration.snapshot,
                processorOwnerDeliveryDelay: processorOwnerDeliveryDelay.snapshot,
                processorEndToEndDuration: processorEndToEndDuration.snapshot,
                processedFrameWriterWaitDuration: processedFrameWriterWaitDuration.snapshot,
                sessionDuration: Self.seconds(from: startTime, to: snapshotTime),
                finishingDuration: Self.seconds(from: finishingStartTime, to: snapshotTime),
                isFinal: isFinal
            )
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func elapsed(from start: UInt64, to end: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }

    private static func seconds(from start: UInt64?, to end: UInt64) -> TimeInterval {
        guard let start else { return 0 }
        return TimeInterval(elapsed(from: start, to: end)) / 1_000_000_000
    }
}
