//
//  MediaPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public final class MediaProcessorChain: MediaSink {
    public var processors: [FrameProcessor] {
        get { node.processors }
        set { node.processors = newValue }
    }

    public var sinks: [MediaSink] {
        get { node.sinks }
        set { node.sinks = newValue }
    }

    public var errorHandler: ((Error) -> Void)? {
        get { node.errorHandler }
        set { node.errorHandler = newValue }
    }

    public var completionHandler: (() -> Void)?

    let node: MediaConsumerChainNode

    public init(processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.node = MediaConsumerChainNode(processors: processors, sinks: sinks)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        node.consume(frame, from: node, completion: completion)
    }

    public func pause() {
        node.pause()
    }

    public func resume() {
        node.resume()
    }

    public func cancel() {
        node.cancel()
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        node.finish { [weak self] result in
            if case .success = result {
                self?.completionHandler?()
            }
            completion(result)
        }
    }
}

public final class MediaPipeline {
    public let source: MediaSource
    public let chain: MediaProcessorChain

    public var processors: [FrameProcessor] {
        get { chain.processors }
        set { chain.processors = newValue }
    }

    public var sinks: [MediaSink] {
        get { chain.sinks }
        set { chain.sinks = newValue }
    }

    public var errorHandler: ((Error) -> Void)? {
        get { chain.errorHandler }
        set {
            chain.errorHandler = newValue
            sourceAdapter.errorHandler = newValue
        }
    }

    public var completionHandler: (() -> Void)? {
        get { chain.completionHandler }
        set {
            chain.completionHandler = newValue
            sourceAdapter.finishHandler = { [weak self] in
                self?.finishChain()
            }
        }
    }

    private let sourceAdapter: MediaSourceNodeAdapter
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-pipeline.state")
    private var hasFinished = false

    public init(source: MediaSource, processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.source = source
        self.chain = MediaProcessorChain(processors: processors, sinks: sinks)
        self.sourceAdapter = MediaSourceNodeAdapter(source: source)
        self.sourceAdapter.add(consumer: chain.node)
        self.sourceAdapter.finishHandler = { [weak self] in
            self?.finishChain()
        }
    }

    public convenience init(source: MediaSource, branch: MediaGraphBranch) {
        self.init(source: source, processors: branch.processors, sinks: branch.sinks)
    }

    public func start() {
        source.start()
    }

    public func pause() {
        source.pause()
        chain.pause()
    }

    public func resume() {
        source.resume()
        chain.resume()
    }

    public func stop() {
        source.stop()
        finishChain()
    }

    public func cancel() {
        source.cancel()
        chain.cancel()
    }

    private func finishChain() {
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }

        chain.finish { [weak self] result in
            if case .failure(let error) = result {
                self?.errorHandler?(error)
            }
        }
    }
}

public extension MediaPipeline {
    func makeBranch(children: [MediaGraphBranch] = []) -> MediaGraphBranch {
        MediaGraphBranch(
            processors: processors,
            sinks: sinks,
            children: children
        )
    }
}
