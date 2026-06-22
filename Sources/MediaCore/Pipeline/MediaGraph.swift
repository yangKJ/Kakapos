//
//  MediaGraph.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public final class MediaGraphBranch {
    public let id: UUID
    public var processors: [FrameProcessor]
    public var sinks: [MediaSink]
    public var children: [MediaGraphBranch]
    public var isEnabled: Bool

    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-graph-branch.state")
    private var branchNode: MediaGraphBranchNode?

    public init(
        id: UUID = UUID(),
        processors: [FrameProcessor] = [],
        sinks: [MediaSink] = [],
        children: [MediaGraphBranch] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.processors = processors
        self.sinks = sinks
        self.children = children
        self.isEnabled = isEnabled
    }

    public func append(_ child: MediaGraphBranch) {
        children.append(child)
        branchNode?.rebuild()
    }

    public func append(sink: MediaSink) {
        sinks.append(sink)
        branchNode?.rebuild()
    }

    public func append(processor: FrameProcessor) {
        processors.append(processor)
        branchNode?.rebuild()
    }

    func attachErrorHandlerRecursively(_ errorHandler: ((Error) -> Void)?) {
        branchNode?.errorHandler = errorHandler
        children.forEach { $0.attachErrorHandlerRecursively(errorHandler) }
    }

    func materializeNode(errorHandler: ((Error) -> Void)? = nil) -> MediaGraphBranchNode {
        stateQueue.sync {
            if let branchNode {
                branchNode.rebuild()
                branchNode.errorHandler = errorHandler
                return branchNode
            }
            let branchNode = MediaGraphBranchNode(branch: self, errorHandler: errorHandler)
            self.branchNode = branchNode
            return branchNode
        }
    }

    func pause() {
        materializeNode().pause()
    }

    func resume() {
        materializeNode().resume()
    }

    func cancel() {
        materializeNode().cancel()
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        materializeNode().finish(completion: completion)
    }

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        materializeNode().consume(frame, from: materializeNode(), completion: completion)
    }
}

public final class MediaGraph {
    public let source: MediaSource
    public private(set) var branches: [MediaGraphBranch]
    public var errorHandler: ((Error) -> Void)? {
        didSet {
            sourceAdapter.errorHandler = errorHandler
            branches.forEach { $0.attachErrorHandlerRecursively(errorHandler) }
        }
    }
    public var completionHandler: (() -> Void)?
    public var frameHandler: ((MediaFrame) -> Void)? {
        didSet {
            sourceAdapter.frameHandler = frameHandler
        }
    }

    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-graph.state")
    private var hasFinished = false
    private let sourceAdapter: MediaSourceNodeAdapter

    public init(
        source: MediaSource,
        branches: [MediaGraphBranch] = []
    ) {
        self.source = source
        self.branches = branches
        self.sourceAdapter = MediaSourceNodeAdapter(source: source)
        self.sourceAdapter.finishHandler = { [weak self] in
            self?.finishBranches()
        }
        self.sourceAdapter.frameHandler = frameHandler
        rebuildConnections()
    }

    public func append(_ branch: MediaGraphBranch) {
        branches.append(branch)
        branch.attachErrorHandlerRecursively(errorHandler)
        rebuildConnections()
    }

    public func start() {
        source.start()
    }

    public func pause() {
        source.pause()
        branches.forEach { $0.pause() }
    }

    public func resume() {
        source.resume()
        branches.forEach { $0.resume() }
    }

    public func stop() {
        source.stop()
        finishBranches()
    }

    public func cancel() {
        source.cancel()
        branches.forEach { $0.cancel() }
    }

    private func rebuildConnections() {
        sourceAdapter.removeAllConsumers()
        branches.forEach { branch in
            branch.attachErrorHandlerRecursively(errorHandler)
            sourceAdapter.add(consumer: branch.materializeNode(errorHandler: errorHandler))
        }
    }

    private func finishBranches() {
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }

        guard !branches.isEmpty else {
            completionHandler?()
            return
        }

        let lock = NSLock()
        var remainingBranches = branches.count
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
            if case .failure(let error) = result {
                self.errorHandler?(error)
            } else {
                self.completionHandler?()
            }
        }

        for branch in branches {
            branch.finish { result in
                lock.lock()
                if case .failure(let error) = result, capturedError == nil {
                    capturedError = error
                }
                if remainingBranches > 0 {
                    remainingBranches -= 1
                }
                let shouldComplete = remainingBranches == 0
                lock.unlock()

                if shouldComplete {
                    finishIfNeeded()
                }
            }
        }
    }
}

final class MediaGraphBranchNode: MediaFrameConsumerNode, MediaFrameSourceNode {
    private let branch: MediaGraphBranch
    private let outputNode = MediaOutputNode()
    private var chainNode: MediaConsumerChainNode

    var errorHandler: ((Error) -> Void)? {
        didSet {
            chainNode.errorHandler = errorHandler
            childNodes.forEach { $0.errorHandler = errorHandler }
        }
    }

    private var childNodes: [MediaGraphBranchNode] = []

    init(branch: MediaGraphBranch, errorHandler: ((Error) -> Void)? = nil) {
        self.branch = branch
        self.chainNode = MediaConsumerChainNode(processors: branch.processors, sinks: branch.sinks)
        self.errorHandler = errorHandler
        self.chainNode.errorHandler = errorHandler
        rebuild()
    }

    func rebuild() {
        chainNode.processors = branch.processors
        chainNode.sinks = branch.sinks
        chainNode.errorHandler = errorHandler

        outputNode.removeAllConsumers()
        outputNode.add(consumer: chainNode)

        childNodes = branch.children.map { child in
            let node = child.materializeNode(errorHandler: errorHandler)
            node.rebuild()
            return node
        }
        childNodes.forEach { outputNode.add(consumer: $0) }
    }

    @discardableResult
    func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        guard branch.isEnabled else {
            completion(.success(()))
            return
        }
        outputNode.transmit(frame) { [weak self] result in
            if case .failure(let error) = result {
                self?.errorHandler?(error)
            }
            completion(result)
        }
    }

    func pause() {
        chainNode.pause()
        childNodes.forEach { $0.pause() }
    }

    func resume() {
        chainNode.resume()
        childNodes.forEach { $0.resume() }
    }

    func cancel() {
        chainNode.cancel()
        childNodes.forEach { $0.cancel() }
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        guard branch.isEnabled else {
            completion(.success(()))
            return
        }

        let lock = NSLock()
        var remainingChildren = childNodes.count + 1
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

        chainNode.finish { result in
            lock.lock()
            if case .failure(let error) = result, capturedError == nil {
                capturedError = error
            }
            if remainingChildren > 0 {
                remainingChildren -= 1
            }
            let shouldComplete = remainingChildren == 0
            lock.unlock()

            if shouldComplete {
                finishIfNeeded()
            }
        }

        for child in childNodes {
            child.finish { result in
                lock.lock()
                if case .failure(let error) = result, capturedError == nil {
                    capturedError = error
                }
                if remainingChildren > 0 {
                    remainingChildren -= 1
                }
                let shouldComplete = remainingChildren == 0
                lock.unlock()

                if shouldComplete {
                    finishIfNeeded()
                }
            }
        }
    }
}
