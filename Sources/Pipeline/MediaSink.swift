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

    private enum MetadataKey {
        static let frameRequestReason = "kakapos.player-frame-request-reason"
    }

    public struct Snapshot: Equatable {
        public let state: State
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastSourceTime: CMTime?
        public let lastFrameRequestReason: String?
        public let pendingFrameIndex: Int64?
        public let pendingFramePresentationTime: CMTime?
        public let pendingFrameSourceTime: CMTime?
        public let pendingFrameRequestReason: String?
        public let lastImageWidth: Int?
        public let lastImageHeight: Int?
        public let hasPendingFrame: Bool
    }

    public struct Summary {
        public let state: State
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastSourceTime: CMTime?
        public let lastFrameRequestReason: String?
        public let pendingFrameIndex: Int64?
        public let pendingFramePresentationTime: CMTime?
        public let pendingFrameSourceTime: CMTime?
        public let pendingFrameRequestReason: String?
        public let lastImageWidth: Int?
        public let lastImageHeight: Int?
        public let hasPendingFrame: Bool

        public var summaryText: String {
            let frameText = lastFrameIndex.map(String.init) ?? "n/a"
            let presentationText = lastPresentationTime.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            let sourceTimeText = lastSourceTime.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            let reasonText = lastFrameRequestReason ?? "n/a"
            let sizeText: String
            if let lastImageWidth, let lastImageHeight {
                sizeText = "\(lastImageWidth)x\(lastImageHeight)"
            } else {
                sizeText = "n/a"
            }
            var text = "state \(state) · frame \(frameText) · presentation \(presentationText) · sourceTime \(sourceTimeText) · reason \(reasonText) · image \(sizeText) · pending \(hasPendingFrame ? "yes" : "no")"
            if hasPendingFrame, let pendingFrameIndex, let pendingFrameRequestReason {
                text += " · pendingFrame \(pendingFrameIndex)"
                if let pendingFramePresentationTime {
                    text += " · pendingPresentation \(String(format: "%.2fs", pendingFramePresentationTime.seconds))"
                }
                if let pendingFrameSourceTime {
                    text += " · pendingSourceTime \(String(format: "%.2fs", pendingFrameSourceTime.seconds))"
                }
                text += " · pendingReason \(pendingFrameRequestReason)"
            }
            return text
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

    public var snapshot: Snapshot {
        lock.lock()
        let snapshot = Snapshot(
            state: state,
            lastFrameIndex: lastFrame?.metadata.frameIndex,
            lastPresentationTime: lastFrame?.metadata.presentationTime,
            lastSourceTime: lastFrame?.metadata.sourceTime ?? lastFrame?.metadata.presentationTime,
            lastFrameRequestReason: lastFrame?.metadata.userInfo[MetadataKey.frameRequestReason] as? String,
            pendingFrameIndex: pendingFrame?.metadata.frameIndex,
            pendingFramePresentationTime: pendingFrame?.metadata.presentationTime,
            pendingFrameSourceTime: pendingFrame?.metadata.sourceTime ?? pendingFrame?.metadata.presentationTime,
            pendingFrameRequestReason: pendingFrame?.metadata.userInfo[MetadataKey.frameRequestReason] as? String,
            lastImageWidth: lastImage?.width,
            lastImageHeight: lastImage?.height,
            hasPendingFrame: pendingFrame != nil
        )
        lock.unlock()
        return snapshot
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
        return Summary(
            state: currentSnapshot.state,
            lastFrameIndex: currentSnapshot.lastFrameIndex,
            lastPresentationTime: currentSnapshot.lastPresentationTime,
            lastSourceTime: currentSnapshot.lastSourceTime,
            lastFrameRequestReason: currentSnapshot.lastFrameRequestReason,
            pendingFrameIndex: currentSnapshot.pendingFrameIndex,
            pendingFramePresentationTime: currentSnapshot.pendingFramePresentationTime,
            pendingFrameSourceTime: currentSnapshot.pendingFrameSourceTime,
            pendingFrameRequestReason: currentSnapshot.pendingFrameRequestReason,
            lastImageWidth: currentSnapshot.lastImageWidth,
            lastImageHeight: currentSnapshot.lastImageHeight,
            hasPendingFrame: currentSnapshot.hasPendingFrame
        )
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
        let currentState = state
        let isPaused = currentState == .paused
        let isTerminal = currentState == .finished || currentState == .cancelled
        if isTerminal {
            lock.unlock()
            completion(.success(()))
            return
        }
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
        lock.lock()
        let isTerminal = state == .finished || state == .cancelled
        lock.unlock()
        guard isTerminal == false else { return }
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
        lock.lock()
        pendingFrame = nil
        lock.unlock()
        updateState(.finished)
        completion(.success(()))
    }

    private func updateState(_ newState: State) {
        lock.lock()
        if state == .finished || state == .cancelled {
            lock.unlock()
            return
        }
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
