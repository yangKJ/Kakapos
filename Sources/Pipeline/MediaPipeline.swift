//
//  MediaPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public final class MediaPipeline: MediaSourceDelegate {
    public let source: MediaSource
    public var processors: [FrameProcessor]
    public var sinks: [MediaSink]
    public var errorHandler: ((Error) -> Void)?
    public var completionHandler: (() -> Void)?
    private var hasFinishedSinks = false
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-pipeline.state")

    public init(source: MediaSource, processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.source = source
        self.processors = processors
        self.sinks = sinks
        self.source.delegate = self
    }

    public func start() {
        source.start()
    }

    public func pause() {
        source.pause()
    }

    public func resume() {
        source.resume()
    }

    public func stop() {
        source.stop()
        finishSinks()
    }

    public func cancel() {
        source.cancel()
    }

    public func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {
        process(frame, at: 0)
    }

    public func mediaSource(_ source: MediaSource, didFail error: Error) {
        errorHandler?(error)
    }

    public func mediaSourceDidFinish(_ source: MediaSource) {
        finishSinks()
    }

    private func process(_ frame: MediaFrame, at index: Int) {
        guard index < processors.count else {
            consume(frame, at: 0)
            return
        }
        processors[index].process(frame) { [weak self] result in
            switch result {
            case .success(let processedFrame):
                self?.process(processedFrame, at: index + 1)
            case .failure(let error):
                self?.errorHandler?(error)
            }
        }
    }

    private func consume(_ frame: MediaFrame, at index: Int) {
        guard index < sinks.count else { return }
        sinks[index].consume(frame) { [weak self] result in
            switch result {
            case .success:
                self?.consume(frame, at: index + 1)
            case .failure(let error):
                self?.errorHandler?(error)
            }
        }
    }

    private func finishSinks() {
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinishedSinks else { return false }
            hasFinishedSinks = true
            return true
        }
        guard shouldFinish else { return }
        guard !sinks.isEmpty else {
            completionHandler?()
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
            } else {
                self?.completionHandler?()
            }
        }
    }
}
