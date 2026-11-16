//
//  MediaNode.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public protocol MediaFrameSourceNode: AnyObject {
    @discardableResult
    func add<T: MediaFrameConsumerNode>(consumer: T) -> T
    func add(consumer: MediaFrameConsumerNode, at index: Int)
    func remove(consumer: MediaFrameConsumerNode)
    func removeAllConsumers()
}

public protocol MediaFrameConsumerNode: AnyObject {
    func add(source: MediaFrameSourceNode)
    func remove(source: MediaFrameSourceNode)
    /// 每个已接收帧必须且只能完成一次；未调用 completion 会持续占用上游背压槽位。
    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void)
}

public extension MediaFrameConsumerNode {
    func add(source: MediaFrameSourceNode) {}
    func remove(source: MediaFrameSourceNode) {}
}

final class MediaNodeResultState {
    private let lock = NSLock()
    private var capturedError: Error?

    var result: Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let capturedError {
            return .failure(capturedError)
        }
        return .success(())
    }

    func capture(_ result: Result<Void, Error>) {
        guard case .failure(let error) = result else { return }
        lock.lock()
        defer { lock.unlock() }
        guard capturedError == nil else { return }
        capturedError = error
    }
}

/// 汇总一次分发或收尾：每个槽位只确认一次，保留首次错误，在最后确认的线程回调。
final class MediaCompletionGroup {
    private let lock = NSLock()
    private var completed: [Bool]
    private var remaining: Int
    private var firstError: Error?
    private var completion: ((Result<Void, Error>) -> Void)?

    init(count: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        completed = Array(repeating: false, count: count)
        remaining = count
        self.completion = completion
    }

    func complete(at index: Int, with result: Result<Void, Error>) {
        lock.lock()
        guard !completed[index] else { lock.unlock(); return }
        completed[index] = true
        if case .failure(let error) = result, firstError == nil {
            firstError = error
        }
        remaining -= 1
        guard remaining == 0 else { lock.unlock(); return }
        let callback = completion
        completion = nil
        let finalResult: Result<Void, Error>
        if let firstError {
            finalResult = .failure(firstError)
        } else {
            finalResult = .success(())
        }
        lock.unlock()
        callback?(finalResult)
    }
}

open class MediaOutputNode: MediaFrameSourceNode {
    private let lock = NSLock()
    private var consumersStorage: [MediaFrameConsumerNode] = []

    public init() {}

    open var consumers: [MediaFrameConsumerNode] {
        lock.lock()
        defer { lock.unlock() }
        return consumersStorage
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        lock.lock()
        consumersStorage.append(consumer)
        lock.unlock()
        consumer.add(source: self)
        return consumer
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        lock.lock()
        let insertionIndex = max(0, min(index, consumersStorage.count))
        consumersStorage.insert(consumer, at: insertionIndex)
        lock.unlock()
        consumer.add(source: self)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        lock.lock()
        let hadConsumer = consumersStorage.contains { candidate in
            ObjectIdentifier(candidate) == ObjectIdentifier(consumer)
        }
        consumersStorage.removeAll { candidate in
            ObjectIdentifier(candidate) == ObjectIdentifier(consumer)
        }
        lock.unlock()
        if hadConsumer {
            consumer.remove(source: self)
        }
    }

    public func removeAllConsumers() {
        let detachedConsumers: [MediaFrameConsumerNode]
        lock.lock()
        detachedConsumers = consumersStorage
        consumersStorage.removeAll()
        lock.unlock()
        detachedConsumers.forEach { $0.remove(source: self) }
    }

    public func transmit(
        _ frame: MediaFrame,
        consumers selectedConsumers: [MediaFrameConsumerNode]? = nil,
        shouldContinue: () -> Bool = { true },
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let consumers = selectedConsumers ?? self.consumers
        guard !consumers.isEmpty else {
            completion(.success(()))
            return
        }

        let group = MediaCompletionGroup(count: consumers.count, completion: completion)
        for (index, consumer) in consumers.enumerated() {
            guard shouldContinue() else {
                for skippedIndex in index..<consumers.count {
                    group.complete(at: skippedIndex, with: .success(()))
                }
                break
            }
            consumer.consume(frame, from: self) { result in
                group.complete(at: index, with: result)
            }
        }
    }
}

public final class MediaProcessorNode: MediaOutputNode, MediaFrameConsumerNode, @unchecked Sendable {
    private final class Work: @unchecked Sendable {
        let id = UUID()
        let processors: [FrameProcessor]
        let consumers: [MediaFrameConsumerNode]
        let completion: (Result<Void, Error>) -> Void
        let lock = NSLock()
        var operation: FrameProcessingOperation?
        var stage: UInt64 = 0
        var completed = false
        var processingEnded = false
        var cancellationRequested = false
        var timeout: DispatchWorkItem?
        var ordinal: UInt64?
        var input: MediaFrame?
        var processing = false
        let concurrencyLimit: Int

        init(processors: [FrameProcessor], consumers: [MediaFrameConsumerNode], completion: @escaping (Result<Void, Error>) -> Void) {
            self.processors = processors
            self.concurrencyLimit = processors.compactMap { ($0 as? FrameProcessorCapabilityProviding)?.capabilities.maximumConcurrentFrameCount }.min() ?? Int.max
            self.consumers = consumers
            self.completion = completion
        }

        var isActive: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !completed
        }

        func finish(_ result: Result<Void, Error>) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            if case .failure = result { cancellationRequested = true }
            timeout?.cancel()
            timeout = nil
            let operation = self.operation
            self.operation = nil
            lock.unlock()
            if case .failure = result { operation?.cancel() }
            completion(result)
        }
    }

    private let processingQueue = DispatchQueue(label: "com.condy.kakapos.processor-node", qos: .userInitiated)
    private let configurationLock = NSLock()
    private var processorStorage: [FrameProcessor]
    private var works: [UUID: Work] = [:]
    private var cancelled = false
    private var nextOrdinal: UInt64 = 0
    private var nextDeliveryOrdinal: UInt64 = 0
    private var ready: [UInt64: (Work, Result<MediaFrame, Error>)] = [:]
    private var draining = false
    private var pending: [Work] = []
    private var pendingCursor = 0
    private var processingCount = 0
    private var processingLimits: [UUID: Int] = [:]
    public var errorHandler: ((Error) -> Void)?
    public var processesAudioFrames = true
    var queuedWorkStorageCount: Int { configurationLock.withKakaposLock { pending.count } }
    private var processingTimeoutStorage: TimeInterval?
    public var frameProcessingTimeout: TimeInterval? {
        get { configurationLock.withKakaposLock { processingTimeoutStorage } }
        set { configurationLock.withKakaposLock { processingTimeoutStorage = newValue.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } } }
    }

    public var processors: [FrameProcessor] {
        get { configurationLock.withKakaposLock { processorStorage } }
        set { configurationLock.withKakaposLock { processorStorage = newValue } }
    }

    public init(processors: [FrameProcessor] = []) {
        processorStorage = processors
        super.init()
    }

    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        consume(frame, processors: processors, consumers: consumers, completion: completion)
    }

    func consume(_ frame: MediaFrame, processors: [FrameProcessor], consumers: [MediaFrameConsumerNode], completion: @escaping (Result<Void, Error>) -> Void) {
        let activeProcessors = !processesAudioFrames && isAudioMediaFrame(frame) ? [] : processors
        let work = Work(processors: activeProcessors, consumers: consumers, completion: completion)
        let accepted = configurationLock.withKakaposLock { () -> Bool in
            guard !cancelled else { return false }
            if processesAudioFrames || !isAudioMediaFrame(frame) {
                work.ordinal = nextOrdinal
                nextOrdinal &+= 1
            }
            works[work.id] = work
            return true
        }
        guard accepted else { work.finish(.failure(MediaCoreError.processingCancelled)); return }
        if !activeProcessors.isEmpty, let duration = frameProcessingTimeout, duration.isFinite, duration > 0 {
            let timer = DispatchWorkItem { [weak self, weak work] in
                guard let self, let work else { return }
                self.failTimedOut(work)
            }
            work.lock.lock(); work.timeout = timer; let completed = work.completed; work.lock.unlock()
            if completed { timer.cancel() }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + duration, execute: timer)
        }
        // 无处理器的直通路径不增加排队；有处理器时只在专用队列执行。
        if activeProcessors.isEmpty {
            process(frame, at: 0, work: work)
        } else {
            configurationLock.withKakaposLock {
                if !cancelled, works[work.id] != nil { work.input = frame; pending.append(work) }
            }
            schedulePending()
        }
    }

    func cancelProcessing() -> [MediaSink] {
        let pending = configurationLock.withKakaposLock { () -> [Work] in
            cancelled = true
            let pending = Array(works.values)
            works.removeAll()
            self.pending.removeAll()
            pendingCursor = 0
            ready.removeAll()
            nextDeliveryOrdinal = nextOrdinal
            processingCount = 0
            processingLimits.removeAll()
            return pending
        }
        let sinks = pending.flatMap { $0.consumers.compactMap { ($0 as? MediaSinkNode)?.sink } }
        pending.forEach { $0.finish(.failure(MediaCoreError.processingCancelled)) }
        return sinks
    }

    private func complete(_ work: Work, result: Result<Void, Error>) {
        let active = configurationLock.withKakaposLock { works.removeValue(forKey: work.id) != nil }
        guard active else { return }
        work.finish(result)
        if case .failure(let error) = result { errorHandler?(error) }
    }

    private func process(_ frame: MediaFrame, at index: Int, work: Work) {
        work.lock.lock(); let accepts = !work.completed && !work.processingEnded; work.lock.unlock()
        guard accepts else { return }
        guard index < work.processors.count else {
            enqueue(.success(frame), work: work)
            return
        }
        work.lock.lock()
        work.stage &+= 1
        let stage = work.stage
        work.lock.unlock()
        let operation = processFrame(using: work.processors[index], frame: frame) { [weak self, weak work] result in
            guard let self, let work else { return }
            work.lock.lock()
            guard !work.completed, !work.processingEnded, work.stage == stage else { work.lock.unlock(); return }
            work.stage &+= 1
            work.operation = nil
            work.lock.unlock()
            switch result {
            case .success(let output):
                let outputBox = ProcessingTransfer(value: output)
                self.processingQueue.async { self.process(outputBox.value, at: index + 1, work: work) }
            case .failure(let error):
                self.enqueue(.failure(error), work: work)
            }
        }
        work.lock.lock()
        let shouldInstall = !work.completed && !work.processingEnded && work.stage == stage
        if shouldInstall { work.operation = operation }
        let wasCancelled = work.cancellationRequested
        work.lock.unlock()
        if wasCancelled { operation?.cancel() }
    }
    private func failTimedOut(_ work: Work) {
        let pending = configurationLock.withKakaposLock { () -> [Work] in
            guard works[work.id] != nil else { return [] }
            work.lock.lock()
            let active = !work.completed && !work.processingEnded
            work.lock.unlock()
            guard active else { return [] }
            cancelled = true
            let values = Array(works.values)
            works.removeAll(); ready.removeAll(); self.pending.removeAll()
            pendingCursor = 0; processingCount = 0; processingLimits.removeAll()
            nextDeliveryOrdinal = nextOrdinal
            return values
        }
        guard !pending.isEmpty else { return }
        pending.forEach { $0.finish(.failure(MediaCoreError.frameProcessingTimedOut)) }
        errorHandler?(MediaCoreError.frameProcessingTimedOut)
    }

    private func schedulePending() {
        while true {
            let next = configurationLock.withKakaposLock { () -> (Work, MediaFrame)? in
                guard !cancelled, pendingCursor < pending.count else { return nil }
                let work = pending[pendingCursor]
                let limit = min(work.concurrencyLimit, processingLimits.values.min() ?? Int.max)
                guard processingCount < limit, let frame = work.input else { return nil }
                pendingCursor += 1
                if pendingCursor == pending.count {
                    pending.removeAll(keepingCapacity: true); pendingCursor = 0
                } else if pendingCursor >= 64 && pendingCursor >= pending.count / 2 {
                    // 持续背压时队尾不断加入新帧，也必须释放已经消费的队列前缀。
                    pending.removeFirst(pendingCursor); pendingCursor = 0
                }
                work.input = nil
                work.processing = true
                processingCount += 1
                if work.concurrencyLimit != Int.max { processingLimits[work.id] = work.concurrencyLimit }
                return (work, frame)
            }
            guard let (work, frame) = next else { return }
            let box = ProcessingTransfer(value: frame)
            processingQueue.async { self.process(box.value, at: 0, work: work) }
        }
    }

    private func enqueue(_ result: Result<MediaFrame, Error>, work: Work) {
        var cancellation: FrameProcessingOperation?
        let action = configurationLock.withKakaposLock { () -> (accepted: Bool, drain: Bool) in
            guard works[work.id] != nil else { return (false, false) }
            work.lock.lock()
            guard !work.completed, !work.processingEnded else { work.lock.unlock(); return (false, false) }
            work.processingEnded = true
            work.timeout?.cancel(); work.timeout = nil
            if case .failure = result { work.cancellationRequested = true }
            let operation = work.operation
            work.operation = nil
            work.lock.unlock()
            if case .failure = result { cancellation = operation }
            if work.processing {
                work.processing = false
                processingCount -= 1
                processingLimits.removeValue(forKey: work.id)
            }
            guard let ordinal = work.ordinal else { return (true, false) }
            ready[ordinal] = (work, result)
            guard !draining else { return (true, false) }
            draining = true
            return (true, true)
        }
        cancellation?.cancel()
        guard action.accepted else { return }
        if work.ordinal == nil { deliver(result, work: work) }
        if action.drain { drainReady() }
        schedulePending()
    }

    private func drainReady() {
        while true {
            let next = configurationLock.withKakaposLock { () -> (Work, Result<MediaFrame, Error>)? in
                guard let value = ready.removeValue(forKey: nextDeliveryOrdinal) else { draining = false; return nil }
                nextDeliveryOrdinal &+= 1
                return value
            }
            guard let (work, result) = next else { return }
            deliver(result, work: work)
        }
    }

    private func deliver(_ result: Result<MediaFrame, Error>, work: Work) {
        switch result {
        case .success(let frame):
            transmit(frame, consumers: work.consumers, shouldContinue: { work.isActive }) { self.complete(work, result: $0) }
        case .failure(let error): complete(work, result: .failure(error))
        }
    }

}

private struct ProcessingTransfer<Value>: @unchecked Sendable {
    let value: Value
}

public final class MediaSinkNode: MediaFrameConsumerNode {
    public let sink: MediaSink

    public init(sink: MediaSink) {
        self.sink = sink
    }

    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        sink.consume(frame, completion: completion)
    }
}

public final class MediaSourceNodeAdapter: NSObject, MediaSourceDelegate, MediaFrameSourceNode, BoundedMediaSourceDelegate {
    public let source: MediaSource
    public var errorHandler: ((Error) -> Void)?
    public var finishHandler: (() -> Void)?
    public var frameHandler: ((MediaFrame) -> Void)?
    public var frameTransmissionStartedHandler: (() -> Void)?
    public var frameTransmissionCompletedHandler: ((Result<Void, Error>) -> Void)?
    public var shouldAcceptSourceCallbacks: (() -> Bool)?
    public var deliveryPolicy: MediaSourceDeliveryPolicy = .unbounded
    public var acceptsAudioFrames = true
    public var managesFrameBackpressure: Bool {
        deliveryPolicy.normalizedMaximumInFlightFrames != nil && (!acceptsAudioFrames || maximumInFlightAudioFrameCount != nil)
    }
    public var droppedFrameHandler: ((MediaFrame) -> Void)?

    /// 供同模块内需要原子登记在途帧的编排器使用。
    /// 返回 `true` 表示该帧已被生命周期 owner 接受并计入在途工作。
    var sourceFrameAcceptanceHandler: (() -> Bool)?

    private let outputNode = MediaOutputNode()
    private let deliveryLock = NSLock()
    private var inFlightDeliveryCount = 0
    private var pendingLatestFrame: MediaFrame?
    private var pendingLatestCompletion: ((Result<Void, Error>) -> Void)?
    public var maximumInFlightAudioFrameCount: Int?
    private var inFlightAudioCount = 0
    private var sourceDidFinishDelivery = false
    private var didDeliverFinish = false

    public init(source: MediaSource) {
        self.source = source
        super.init()
        if let multiplexingSource = source as? MediaSourceDelegateMultiplexing {
            multiplexingSource.addMediaSourceDelegate(self, delivery: .processing)
        } else {
            self.source.delegate = self
        }
    }

    deinit {
        if let multiplexingSource = source as? MediaSourceDelegateMultiplexing {
            multiplexingSource.removeMediaSourceDelegate(self)
        } else if source.delegate === self {
            source.delegate = nil
        }
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    public func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }

    public func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {
        mediaSource(source, didOutput: frame, completion: { _ in })
    }

    public func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard shouldAcceptSourceCallbacks?() ?? true else { completion(.success(())); return }
        if !acceptsAudioFrames && isAudioMediaFrame(frame) { completion(.success(())); return }
        if isAudioMediaFrame(frame), let audioCapacity = maximumInFlightAudioFrameCount {
            let accepted = deliveryLock.withKakaposLock { () -> Bool in
                guard inFlightAudioCount < audioCapacity else { return false }
                inFlightAudioCount += 1
                return true
            }
            guard accepted else {
                let error = MediaCoreError.audioDeliveryOverflow
                errorHandler?(error)
                completion(.failure(error))
                return
            }
            transmitAcceptedFrame(frame, audio: true, completion: completion)
            return
        }
        let decision = enqueue(frame, completion: completion)
        if let droppedFrame = decision.droppedFrame { droppedFrameHandler?(droppedFrame) }
        decision.droppedCompletion?(.success(()))
        guard decision.shouldTransmit else {
            if case .latestOnly = deliveryPolicy {} else { completion(.success(())) }
            return
        }
        transmitAcceptedFrame(frame, completion: completion)
    }

    private func transmitAcceptedFrame(_ frame: MediaFrame, audio: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        let acceptsFrame = sourceFrameAcceptanceHandler?() ?? (shouldAcceptSourceCallbacks?() ?? true)
        guard acceptsFrame else {
            completion(.success(()))
            completeDelivery(audio: audio)
            return
        }
        frameTransmissionStartedHandler?()
        frameHandler?(frame)
        outputNode.transmit(frame) { [weak self] result in
            guard let self else { completion(result); return }
            if let handler = self.frameTransmissionCompletedHandler { handler(result) }
            else if case .failure(let error) = result { self.errorHandler?(error) }
            completion(result)
            self.completeDelivery(audio: audio)
        }
    }

    public func mediaSource(_ source: MediaSource, audioDeliveryFailed error: Error) {
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        if maximumInFlightAudioFrameCount != nil { errorHandler?(error) }
    }

    public func mediaSource(_ source: MediaSource, didFail error: Error) {
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        errorHandler?(error)
    }

    public func mediaSourceDidFinish(_ source: MediaSource) {
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        let shouldFinish = deliveryLock.withKakaposLock { () -> Bool in
            sourceDidFinishDelivery = true
            guard inFlightDeliveryCount == 0, inFlightAudioCount == 0, pendingLatestFrame == nil, didDeliverFinish == false else {
                return false
            }
            didDeliverFinish = true
            return true
        }
        if shouldFinish {
            finishHandler?()
        }
    }

    func prepareForStartIfIdle() -> Bool {
        deliveryLock.withKakaposLock {
            guard inFlightDeliveryCount == 0, inFlightAudioCount == 0, pendingLatestFrame == nil else { return false }
            pendingLatestFrame = nil
            sourceDidFinishDelivery = false
            didDeliverFinish = false
            return true
        }
    }

    private func enqueue(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) -> (shouldTransmit: Bool, droppedFrame: MediaFrame?, droppedCompletion: ((Result<Void, Error>) -> Void)?) {
        deliveryLock.withKakaposLock {
            switch deliveryPolicy {
            case .unbounded:
                inFlightDeliveryCount += 1
                return (true, nil, nil)
            case .latestOnly:
                guard inFlightDeliveryCount > 0 else {
                    inFlightDeliveryCount = 1
                    return (true, nil, nil)
                }
                let replacedFrame = pendingLatestFrame
                let replacedCompletion = pendingLatestCompletion
                pendingLatestFrame = frame
                pendingLatestCompletion = completion
                return (false, replacedFrame, replacedCompletion)
            case .boundedDropNewest:
                let maximum = deliveryPolicy.normalizedMaximumInFlightFrames ?? 1
                guard inFlightDeliveryCount < maximum else {
                    return (false, frame, nil)
                }
                inFlightDeliveryCount += 1
                return (true, nil, nil)
            }
        }
    }

    private func completeDelivery(audio: Bool = false) {
        let next = deliveryLock.withKakaposLock { () -> (frame: MediaFrame?, completion: ((Result<Void, Error>) -> Void)?, shouldFinish: Bool) in
            if audio { inFlightAudioCount = max(0, inFlightAudioCount - 1) }
            else { inFlightDeliveryCount = max(0, inFlightDeliveryCount - 1) }
            if !audio, let pendingLatestFrame {
                self.pendingLatestFrame = nil
                let completion = pendingLatestCompletion
                pendingLatestCompletion = nil
                inFlightDeliveryCount += 1
                return (pendingLatestFrame, completion, false)
            }
            guard sourceDidFinishDelivery, inFlightDeliveryCount == 0, inFlightAudioCount == 0, didDeliverFinish == false else {
                return (nil, nil, false)
            }
            didDeliverFinish = true
            return (nil, nil, true)
        }
        if let frame = next.frame {
            transmitAcceptedFrame(frame, completion: next.completion ?? { _ in })
        } else if next.shouldFinish {
            finishHandler?()
        }
    }
}

private extension NSLock {
    func withKakaposLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

public final class MediaConsumerChainNode: MediaOutputNode, MediaFrameConsumerNode {
    public let processorNode: MediaProcessorNode
    private let chainConfigurationLock = NSLock()
    private var sinkStorage: [MediaSinkNode]
    public var sinkNodes: [MediaSinkNode] { chainConfigurationLock.withKakaposLock { sinkStorage } }

    public var processors: [FrameProcessor] {
        get { chainConfigurationLock.withKakaposLock { processorNode.processors } }
        set { chainConfigurationLock.withKakaposLock { processorNode.processors = newValue } }
    }

    public var sinks: [MediaSink] {
        get { sinkNodes.map(\.sink) }
        set { configureSinks(newValue) }
    }

    public var errorHandler: ((Error) -> Void)? {
        didSet {
            processorNode.errorHandler = errorHandler
        }
    }

    public init(processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.processorNode = MediaProcessorNode(processors: processors)
        self.sinkStorage = []
        super.init()
        processorNode.errorHandler = errorHandler
        add(consumer: processorNode)
        configureSinks(sinks)
    }

    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        let snapshot = chainConfigurationLock.withKakaposLock { (processorNode.processors, sinkStorage) }
        let extra = consumers.filter { $0 !== processorNode }
        if extra.isEmpty {
            processorNode.consume(frame, processors: snapshot.0, consumers: snapshot.1, completion: completion)
        } else {
            let frozen = FrozenProcessorConsumer(node: processorNode, processors: snapshot.0, consumers: snapshot.1)
            transmit(frame, consumers: [frozen] + extra, completion: completion)
        }
    }

    public func pause() {
        sinkNodes.forEach { $0.sink.pause() }
    }

    public func resume() {
        sinkNodes.forEach { $0.sink.resume() }
    }

    public func cancel() {
        let pendingSinks = processorNode.cancelProcessing()
        var cancelled: Set<ObjectIdentifier> = []
        for sink in pendingSinks + sinks {
            if cancelled.insert(ObjectIdentifier(sink)).inserted { sink.cancel() }
        }
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        let sinks = self.sinks
        guard !sinks.isEmpty else {
            completion(.success(()))
            return
        }

        let group = MediaCompletionGroup(count: sinks.count, completion: completion)
        for (index, sink) in sinks.enumerated() {
            sink.finish { result in
                group.complete(at: index, with: result)
            }
        }
    }

    private func configureSinks(_ sinks: [MediaSink]) {
        chainConfigurationLock.withKakaposLock {
            processorNode.removeAllConsumers()
            sinkStorage = sinks.map(MediaSinkNode.init(sink:))
            sinkStorage.forEach { processorNode.add(consumer: $0) }
        }
    }
}

private final class FrozenProcessorConsumer: MediaFrameConsumerNode {
    let node: MediaProcessorNode
    let processors: [FrameProcessor]
    let consumers: [MediaFrameConsumerNode]

    init(node: MediaProcessorNode, processors: [FrameProcessor], consumers: [MediaFrameConsumerNode]) {
        self.node = node
        self.processors = processors
        self.consumers = consumers
    }

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        node.consume(frame, processors: processors, consumers: consumers, completion: completion)
    }
}
