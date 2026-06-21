//
//  MediaPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public final class MediaProcessorChain: MediaSink {
    public var processors: [FrameProcessor]
    public var sinks: [MediaSink]
    public var errorHandler: ((Error) -> Void)?
    public var completionHandler: (() -> Void)?

    private var hasFinishedSinks = false
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-processor-chain.state")

    public init(processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.processors = processors
        self.sinks = sinks
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        process(frame, at: 0, completion: completion)
    }

    public func pause() {
        sinks.forEach { $0.pause() }
    }

    public func resume() {
        sinks.forEach { $0.resume() }
    }

    public func cancel() {
        sinks.forEach { $0.cancel() }
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinishedSinks else { return false }
            hasFinishedSinks = true
            return true
        }

        guard shouldFinish else {
            completion(.success(()))
            return
        }

        guard !sinks.isEmpty else {
            completionHandler?()
            completion(.success(()))
            return
        }

        let group = DispatchGroup()
        var capturedError: Error?

        sinks.forEach { sink in
            group.enter()
            sink.finish { result in
                if case .failure(let error) = result, capturedError == nil {
                    capturedError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if let error = capturedError {
                self?.errorHandler?(error)
                completion(.failure(error))
            } else {
                self?.completionHandler?()
                completion(.success(()))
            }
        }
    }

    private func process(_ frame: MediaFrame, at index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < processors.count else {
            consume(frame, at: 0, completion: completion)
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

    private func consume(_ frame: MediaFrame, at index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < sinks.count else {
            completion(.success(()))
            return
        }

        sinks[index].consume(frame) { [weak self] result in
            switch result {
            case .success:
                self?.consume(frame, at: index + 1, completion: completion)
            case .failure(let error):
                self?.errorHandler?(error)
                completion(.failure(error))
            }
        }
    }
}

public final class MediaPipeline: MediaSourceDelegate {
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
        set { chain.errorHandler = newValue }
    }

    public var completionHandler: (() -> Void)? {
        get { chain.completionHandler }
        set { chain.completionHandler = newValue }
    }

    public init(source: MediaSource, processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.source = source
        self.chain = MediaProcessorChain(processors: processors, sinks: sinks)
        self.source.delegate = self
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

    public func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {
        chain.consume(frame) { [weak self] result in
            if case .failure(let error) = result {
                self?.errorHandler?(error)
            }
        }
    }

    public func mediaSource(_ source: MediaSource, didFail error: Error) {
        errorHandler?(error)
    }

    public func mediaSourceDidFinish(_ source: MediaSource) {
        finishChain()
    }

    private func finishChain() {
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
