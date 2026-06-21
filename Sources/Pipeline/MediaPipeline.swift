//
//  MediaPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

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

    public var summary: MediaProcessorChainSummary {
        MediaProcessorChainSummary(
            processorTypeNames: processors.map { String(describing: type(of: $0)) },
            sinkTypeNames: sinks.map { String(describing: type(of: $0)) }
        )
    }

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
    public enum State: Equatable {
        case idle
        case running
        case paused
        case finished
        case cancelled
        case failed
    }

    public let source: MediaSource
    public let chain: MediaProcessorChain
    public private(set) var state: State = .idle

    public var stateHandler: ((State) -> Void)?

    public var processors: [FrameProcessor] {
        get { chain.processors }
        set { chain.processors = newValue }
    }

    public var sinks: [MediaSink] {
        get { chain.sinks }
        set { chain.sinks = newValue }
    }

    public var summary: MediaPipelineSummary {
        MediaPipelineSummary(
            sourceTypeName: String(describing: type(of: source)),
            processorTypeNames: processors.map { String(describing: type(of: $0)) },
            sinkTypeNames: sinks.map { String(describing: type(of: $0)) },
            state: state,
            lastErrorDescription: lastErrorDescription
        )
    }

    public var lastErrorDescription: String? {
        stateQueue.sync { _lastErrorDescription }
    }

    public var errorHandler: ((Error) -> Void)? {
        get { chain.errorHandler }
        set { chain.errorHandler = newValue }
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
    private var _lastErrorDescription: String?

    public init(source: MediaSource, processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.source = source
        self.chain = MediaProcessorChain(processors: processors, sinks: sinks)
        self.sourceAdapter = MediaSourceNodeAdapter(source: source)
        self.sourceAdapter.add(consumer: chain.node)
        self.sourceAdapter.finishHandler = { [weak self] in
            self?.finishChain()
        }
        self.sourceAdapter.errorHandler = { [weak self] error in
            self?.failChain(with: error)
        }
    }

    public convenience init(source: MediaSource, branch: MediaGraphBranch) {
        self.init(source: source, processors: branch.processors, sinks: branch.sinks)
    }

    #if canImport(UIKit)
    public convenience init(player: AVPlayer, processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.init(source: PlayerFrameSource(player: player), processors: processors, sinks: sinks)
    }
    #endif

    public func start() {
        transitionIfNeeded(from: [.idle], to: .running)
        source.start()
    }

    public func pause() {
        source.pause()
        chain.pause()
        transitionIfNeeded(from: [.running], to: .paused)
    }

    public func resume() {
        source.resume()
        chain.resume()
        transitionIfNeeded(from: [.paused], to: .running)
    }

    public func stop() {
        source.stop()
        finishChain()
    }

    public func cancel() {
        transitionIfNeeded(from: [.idle, .running, .paused], to: .cancelled)
        source.cancel()
        chain.cancel()
    }

    private func finishChain() {
        guard transitionIfNeeded(from: [.running, .paused, .idle], to: .finished) else { return }
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }

        chain.finish { [weak self] result in
            if case .failure(let error) = result {
                self?.failChain(with: error, allowFromFinished: true, cancelChain: false)
            }
        }
    }

    private func failChain(with error: Error, allowFromFinished: Bool = false, cancelChain: Bool = true) {
        let errorDescription = Self.errorDescription(for: error)
        stateQueue.sync {
            _lastErrorDescription = errorDescription
        }
        var allowedStates: [State] = [.running, .paused, .idle]
        if allowFromFinished {
            allowedStates.append(.finished)
        }
        guard transitionIfNeeded(from: allowedStates, to: .failed) else { return }
        if cancelChain {
            chain.cancel()
        }
        DispatchQueue.main.async {
            self.errorHandler?(error)
        }
    }

    @discardableResult
    private func transitionIfNeeded(from allowedStates: [State]?, to newState: State) -> Bool {
        let didChange = stateQueue.sync { () -> Bool in
            if let allowedStates, !allowedStates.contains(state) {
                return false
            }
            guard state != newState else { return false }
            state = newState
            return true
        }
        guard didChange else { return false }
        DispatchQueue.main.async {
            self.stateHandler?(newState)
        }
        return true
    }

    private static func errorDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain != NSCocoaErrorDomain {
            return "\(nsError.domain)#\(nsError.code)"
        }
        return nsError.localizedDescription
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
