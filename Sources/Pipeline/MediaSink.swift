//
//  MediaSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import VideoToolbox
import CoreGraphics

public protocol MediaSink: AnyObject {
    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void)
    func pause()
    func resume()
    func cancel()
    func finish(completion: @escaping (Result<Void, Error>) -> Void)
}

public extension MediaSink {
    func pause() {}

    func resume() {}

    func cancel() {}

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

public final class PixelBufferSink: MediaSink {
    public typealias Handler = (MediaFrame) -> Void
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        handler(frame)
        completion(.success(()))
    }
}

public final class PreviewSink: MediaSink {
    public typealias Handler = (CGImage, FrameMetadata) -> Void

    public enum State: Equatable {
        case idle
        case active
        case paused
        case finished
        case cancelled
    }

    private let handler: Handler
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private var pendingFrame: MediaFrame?

    public private(set) var state: State = .idle
    public private(set) var lastFrame: MediaFrame?
    public private(set) var lastImage: CGImage?
    public var stateChangedHandler: ((State) -> Void)?

    public init(
        callbackQueue: DispatchQueue = .main,
        handler: @escaping Handler
    ) {
        self.callbackQueue = callbackQueue
        self.handler = handler
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        let isPaused = state == .paused
        if isPaused {
            pendingFrame = frame
            lock.unlock()
            completion(.success(()))
            return
        }
        lock.unlock()

        guard let pixelBuffer = frame.pixelBuffer else {
            completion(.failure(VideoX.Error.newRenderedPixelBufferForRequestFailure))
            return
        }
        var previewImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &previewImage)
        guard status == noErr, let previewImage else {
            completion(.failure(VideoX.Error.newRenderedPixelBufferForRequestFailure))
            return
        }
        updateState(.active)
        lock.lock()
        lastFrame = frame
        lastImage = previewImage
        lock.unlock()
        callbackQueue.async {
            self.handler(previewImage, frame.metadata)
        }
        completion(.success(()))
    }

    public func pause() {
        updateState(.paused)
    }

    public func resume() {
        let frameToFlush: MediaFrame?
        lock.lock()
        frameToFlush = pendingFrame
        pendingFrame = nil
        lock.unlock()
        updateState(.active)
        guard let frameToFlush else { return }
        consume(frameToFlush) { _ in }
    }

    public func cancel() {
        lock.lock()
        pendingFrame = nil
        lock.unlock()
        updateState(.cancelled)
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        updateState(.finished)
        completion(.success(()))
    }

    private func updateState(_ newState: State) {
        lock.lock()
        guard state != newState else {
            lock.unlock()
            return
        }
        state = newState
        lock.unlock()
        callbackQueue.async {
            self.stateChangedHandler?(newState)
        }
    }
}

extension PreviewSink: MediaFrameConsumerNode {
    public func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        consume(frame, completion: completion)
    }
}
