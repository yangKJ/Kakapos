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

    public struct Summary {
        public let state: State
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastSourceTime: CMTime?
        public let lastImageWidth: Int?
        public let lastImageHeight: Int?
        public let hasPendingFrame: Bool

        public var summaryText: String {
            let frameText = lastFrameIndex.map(String.init) ?? "n/a"
            let presentationText = lastPresentationTime.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            let sourceTimeText = lastSourceTime.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            let sizeText: String
            if let lastImageWidth, let lastImageHeight {
                sizeText = "\(lastImageWidth)x\(lastImageHeight)"
            } else {
                sizeText = "n/a"
            }
            return "state \(state) · frame \(frameText) · presentation \(presentationText) · sourceTime \(sourceTimeText) · image \(sizeText) · pending \(hasPendingFrame ? "yes" : "no")"
        }
    }

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

    public var summary: Summary {
        lock.lock()
        let summary = Summary(
            state: state,
            lastFrameIndex: lastFrame?.metadata.frameIndex,
            lastPresentationTime: lastFrame?.metadata.presentationTime,
            lastSourceTime: lastFrame?.metadata.sourceTime ?? lastFrame?.metadata.presentationTime,
            lastImageWidth: lastImage?.width,
            lastImageHeight: lastImage?.height,
            hasPendingFrame: pendingFrame != nil
        )
        lock.unlock()
        return summary
    }

    public var summaryText: String {
        summary.summaryText
    }

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
