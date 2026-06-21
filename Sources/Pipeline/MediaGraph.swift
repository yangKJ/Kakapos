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
    }

    public func append(sink: MediaSink) {
        sinks.append(sink)
    }

    public func append(processor: FrameProcessor) {
        processors.append(processor)
    }

    func pause() {
        sinks.forEach { $0.pause() }
        children.forEach { $0.pause() }
    }

    func resume() {
        sinks.forEach { $0.resume() }
        children.forEach { $0.resume() }
    }

    func cancel() {
        sinks.forEach { $0.cancel() }
        children.forEach { $0.cancel() }
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        guard isEnabled else {
            completion(.success(()))
            return
        }

        let group = DispatchGroup()
        let state = LockedGraphResult()

        for sink in sinks {
            group.enter()
            sink.finish { result in
                state.capture(result)
                group.leave()
            }
        }

        for child in children {
            group.enter()
            child.finish { result in
                state.capture(result)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(state.result)
        }
    }

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isEnabled else {
            completion(.success(()))
            return
        }
        process(frame, at: 0, completion: completion)
    }

    private func process(_ frame: MediaFrame, at index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < processors.count else {
            route(frame, completion: completion)
            return
        }

        processors[index].process(frame) { [weak self] result in
            switch result {
            case .success(let processedFrame):
                self?.process(processedFrame, at: index + 1, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func route(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        let state = LockedGraphResult()

        for sink in sinks {
            group.enter()
            sink.consume(frame) { result in
                state.capture(result)
                group.leave()
            }
        }

        for child in children {
            group.enter()
            child.consume(frame) { result in
                state.capture(result)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(state.result)
        }
    }
}

public final class MediaGraph: MediaSourceDelegate {
    public let source: MediaSource
    public private(set) var branches: [MediaGraphBranch]
    public var errorHandler: ((Error) -> Void)?
    public var completionHandler: (() -> Void)?
    public var frameHandler: ((MediaFrame) -> Void)?

    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-graph.state")
    private var hasFinished = false

    public init(
        source: MediaSource,
        branches: [MediaGraphBranch] = []
    ) {
        self.source = source
        self.branches = branches
        self.source.delegate = self
    }

    public func append(_ branch: MediaGraphBranch) {
        branches.append(branch)
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

    public func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {
        frameHandler?(frame)
        guard !branches.isEmpty else { return }

        let group = DispatchGroup()
        let state = LockedGraphResult()

        for branch in branches {
            group.enter()
            branch.consume(frame) { result in
                state.capture(result)
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if case .failure(let error) = state.result {
                self?.errorHandler?(error)
            }
        }
    }

    public func mediaSource(_ source: MediaSource, didFail error: Error) {
        errorHandler?(error)
    }

    public func mediaSourceDidFinish(_ source: MediaSource) {
        finishBranches()
    }

    private func finishBranches() {
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }

        let group = DispatchGroup()
        let state = LockedGraphResult()

        for branch in branches {
            group.enter()
            branch.finish { result in
                state.capture(result)
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if case .failure(let error) = state.result {
                self?.errorHandler?(error)
            } else {
                self?.completionHandler?()
            }
        }
    }
}

private final class LockedGraphResult {
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
        if capturedError == nil {
            capturedError = error
        }
    }
}
