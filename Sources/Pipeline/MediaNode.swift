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

    public func transmit(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        let consumers = self.consumers
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

        for consumer in consumers {
            consumer.consume(frame, from: self) { result in
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
        }
    }
}

public final class MediaProcessorNode: MediaOutputNode, MediaFrameConsumerNode {
    public var processors: [FrameProcessor]
    public var errorHandler: ((Error) -> Void)?

    public init(processors: [FrameProcessor] = []) {
        self.processors = processors
        super.init()
    }

    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        process(frame, at: 0, completion: completion)
    }

    private func process(_ frame: MediaFrame, at index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < processors.count else {
            transmit(frame, completion: completion)
            return
        }

        processors[index].process(frame) { [weak self] result in
            switch result {
            case .success(let processedFrame):
                self?.process(processedFrame, at: index + 1, completion: completion)
            case .failure(let error):
                self?.errorHandler?(error)
                completion(.failure(error))
            }
        }
    }
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

    private let outputNode = MediaOutputNode()

    public init(source: MediaSource) {
        self.source = source
        super.init()
        self.source.delegate = self
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
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        frameTransmissionStartedHandler?()
        frameHandler?(frame)
        outputNode.transmit(frame) { [weak self] result in
            self?.frameTransmissionCompletedHandler?(result)
            if case .failure(let error) = result {
                self?.errorHandler?(error)
            }
        }
    }

    public func mediaSource(_ source: MediaSource, didFail error: Error) {
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        errorHandler?(error)
    }

    public func mediaSourceDidFinish(_ source: MediaSource) {
        guard shouldAcceptSourceCallbacks?() ?? true else { return }
        finishHandler?()
    }
}

public final class MediaConsumerChainNode: MediaOutputNode, MediaFrameConsumerNode {
    public let processorNode: MediaProcessorNode
    public private(set) var sinkNodes: [MediaSinkNode]

    public var processors: [FrameProcessor] {
        get { processorNode.processors }
        set { processorNode.processors = newValue }
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
        self.sinkNodes = []
        super.init()
        processorNode.errorHandler = errorHandler
        add(consumer: processorNode)
        configureSinks(sinks)
    }

    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        transmit(frame, completion: completion)
    }

    public func pause() {
        sinkNodes.forEach { $0.sink.pause() }
    }

    public func resume() {
        sinkNodes.forEach { $0.sink.resume() }
    }

    public func cancel() {
        sinkNodes.forEach { $0.sink.cancel() }
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
            sink.finish { result in
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
        processorNode.removeAllConsumers()
        sinkNodes = sinks.map(MediaSinkNode.init(sink:))
        sinkNodes.forEach { processorNode.add(consumer: $0) }
    }
}
