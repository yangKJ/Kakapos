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

        let lock = NSLock()
        var remainingConsumers = consumers.count
        var capturedError: Error?
        var didComplete = false

        func finishIfNeeded() {
            lock.lock()
            guard !didComplete else {
                lock.unlock()
                return
            }
            let result: Result<Void, Error>
            if let capturedError {
                result = .failure(capturedError)
            } else {
                result = .success(())
            }
            didComplete = true
            lock.unlock()
            completion(result)
        }

        func recordCompletion(_ result: Result<Void, Error>) {
            lock.lock()
            if case .failure(let error) = result, capturedError == nil {
                capturedError = error
            }
            if remainingConsumers > 0 {
                remainingConsumers -= 1
            }
            let shouldComplete = remainingConsumers == 0
            lock.unlock()

            if shouldComplete {
                finishIfNeeded()
            }
        }

        for (index, consumer) in consumers.enumerated() {
            guard shouldContinue() else {
                for _ in index..<consumers.count {
                    recordCompletion(.success(()))
                }
                break
            }
            let consumerCompletionLock = NSLock()
            var consumerDidComplete = false
            consumer.consume(frame, from: self) { result in
                consumerCompletionLock.lock()
                guard consumerDidComplete == false else {
                    consumerCompletionLock.unlock()
                    return
                }
                consumerDidComplete = true
                consumerCompletionLock.unlock()
                recordCompletion(result)
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

        init(processors: [FrameProcessor], consumers: [MediaFrameConsumerNode], completion: @escaping (Result<Void, Error>) -> Void) {
            self.processors = processors
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
    public var errorHandler: ((Error) -> Void)?
    public var processesAudioFrames = true

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
            works[work.id] = work
            return true
        }
        guard accepted else { work.finish(.failure(MediaCoreError.processingCancelled)); return }
        // 无处理器的直通路径不增加排队；有处理器时只在专用队列执行。
        if activeProcessors.isEmpty {
            process(frame, at: 0, work: work)
        } else {
            let frameBox = ProcessingTransfer(value: frame)
            processingQueue.async { self.process(frameBox.value, at: 0, work: work) }
        }
    }

    func cancelProcessing() -> [MediaSink] {
        let pending = configurationLock.withKakaposLock { () -> [Work] in
            cancelled = true
            let pending = Array(works.values)
            works.removeAll()
            return pending
        }
        let sinks = pending.flatMap { $0.consumers.compactMap { ($0 as? MediaSinkNode)?.sink } }
        pending.forEach { $0.finish(.failure(MediaCoreError.processingCancelled)) }
        return sinks
    }

    private func complete(_ work: Work, result: Result<Void, Error>) {
        configurationLock.withKakaposLock { _ = works.removeValue(forKey: work.id) }
        work.finish(result)
        if case .failure(let error) = result { errorHandler?(error) }
    }

    private func process(_ frame: MediaFrame, at index: Int, work: Work) {
        guard work.isActive else { return }
        guard index < work.processors.count else {
            transmit(frame, consumers: work.consumers, shouldContinue: { work.isActive }) { result in
                self.complete(work, result: result)
            }
            return
        }
        work.lock.lock()
        work.stage &+= 1
        let stage = work.stage
        work.lock.unlock()
        let operation = processFrame(using: work.processors[index], frame: frame) { [weak self, weak work] result in
            guard let self, let work else { return }
            work.lock.lock()
            guard !work.completed, work.stage == stage else { work.lock.unlock(); return }
            work.stage &+= 1
            work.operation = nil
            work.lock.unlock()
            switch result {
            case .success(let output):
                let outputBox = ProcessingTransfer(value: output)
                self.processingQueue.async { self.process(outputBox.value, at: index + 1, work: work) }
            case .failure(let error):
                self.complete(work, result: .failure(error))
            }
        }
        work.lock.lock()
        let shouldInstall = !work.completed && work.stage == stage
        if shouldInstall { work.operation = operation }
        let wasCancelled = work.completed
        work.lock.unlock()
        if wasCancelled { operation?.cancel() }
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

public final class MediaSourceNodeAdapter: NSObject, MediaSourceDelegate, MediaFrameSourceNode {
    public let source: MediaSource
    public var errorHandler: ((Error) -> Void)?
    public var finishHandler: (() -> Void)?
    public var frameHandler: ((MediaFrame) -> Void)?
    public var frameTransmissionStartedHandler: (() -> Void)?
    public var frameTransmissionCompletedHandler: ((Result<Void, Error>) -> Void)?
    public var shouldAcceptSourceCallbacks: (() -> Bool)?
    public var deliveryPolicy: MediaSourceDeliveryPolicy = .unbounded
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

        let lock = NSLock()
        var remainingSinks = sinks.count
        var capturedError: Error?
        var didComplete = false

        func finishIfNeeded() {
            lock.lock()
            guard !didComplete else {
                lock.unlock()
                return
            }
            let result: Result<Void, Error>
            if let capturedError {
                result = .failure(capturedError)
            } else {
                result = .success(())
            }
            didComplete = true
            lock.unlock()
            completion(result)
        }

        for sink in sinks {
            let sinkCompletionLock = NSLock()
            var sinkDidComplete = false
            sink.finish { result in
                sinkCompletionLock.lock()
                guard sinkDidComplete == false else {
                    sinkCompletionLock.unlock()
                    return
                }
                sinkDidComplete = true
                sinkCompletionLock.unlock()

                lock.lock()
                if case .failure(let error) = result, capturedError == nil {
                    capturedError = error
                }
                if remainingSinks > 0 {
                    remainingSinks -= 1
                }
                let shouldComplete = remainingSinks == 0
                lock.unlock()

                if shouldComplete {
                    finishIfNeeded()
                }
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
