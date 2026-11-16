//
//  MediaSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import VideoToolbox
import CoreGraphics

public enum MediaCoreError: LocalizedError {
    case pixelBufferUnavailable
    case processingNodeUnavailable
    case processingCancelled
    case audioDeliveryOverflow

    public var errorDescription: String? {
        switch self {
        case .pixelBufferUnavailable:
            return "A pixel buffer is required for this media operation."
        case .audioDeliveryOverflow:
            return "Audio delivery capacity was exceeded."
        case .processingCancelled:
            return "Media processing was cancelled."
        case .processingNodeUnavailable:
            return "The media processing node was released before processing completed."
        }
    }
}

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

    private let handler: Handler?
    private let frameHandler: ((MediaFrame) -> Void)?
    private let conversionLock = NSLock()
    private let deliveryFence = NSRecursiveLock()
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private var pendingFrame: MediaFrame?
    private var pendingCallback: (frame: MediaFrame, version: UInt64, completion: (Result<Void, Error>) -> Void)?
    private var lastFrameVersion: UInt64 = 0
    private var imageVersion: UInt64?
    private var imageStorage: CGImage?
    private var convertedFrameCount = 0
    private var coalescedFrameCount = 0
    private var isCallbackScheduled = false
    private var finishRequested = false
    private var finishCompletions: [(Result<Void, Error>) -> Void] = []

    public private(set) var state: State = .idle
    public private(set) var lastFrame: MediaFrame?
    /// 显式读取时按需物化；帧回调路径不会主动转换为 CGImage。
    public var lastImage: CGImage? {
        lock.lock()
        let frame = lastFrame
        let version = lastFrameVersion
        lock.unlock()
        guard let frame else { return nil }
        return try? image(for: frame, version: version)
    }
    public var stateChangedHandler: ((State) -> Void)?

    public var snapshot: Snapshot {
        lock.lock()
        let buffer = lastFrame.flatMap { extractPixelBuffer($0) }
        let width = handler != nil ? buffer.map(CVPixelBufferGetWidth) : (imageVersion == lastFrameVersion ? imageStorage?.width : nil)
        let height = handler != nil ? buffer.map(CVPixelBufferGetHeight) : (imageVersion == lastFrameVersion ? imageStorage?.height : nil)
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
            lastImageWidth: width,
            lastImageHeight: height,
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
        self.frameHandler = nil
    }

    /// 接收原生帧供纹理或像素缓冲宿主显示；可同时保留图像回调。
    public init(callbackQueue: DispatchQueue = .main, frameHandler: @escaping (MediaFrame) -> Void, handler: Handler? = nil) {
        self.callbackQueue = callbackQueue
        self.frameHandler = frameHandler
        self.handler = handler
    }

    var conversionCountsForTesting: (converted: Int, coalesced: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (convertedFrameCount, coalescedFrameCount)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        if state == .finished || state == .cancelled || finishRequested {
            lock.unlock()
            completion(.success(()))
            return
        }
        if state == .paused {
            pendingFrame = frame
            lock.unlock()
            completion(.success(()))
            return
        }
        guard handler == nil || extractPixelBuffer(frame) != nil else {
            lock.unlock()
            completion(.failure(MediaCoreError.pixelBufferUnavailable))
            return
        }
        let replaced = pendingCallback
        if replaced != nil { coalescedFrameCount += 1 }
        lastFrameVersion &+= 1
        lastFrame = frame
        pendingCallback = (frame, lastFrameVersion, completion)
        let schedule = !isCallbackScheduled
        isCallbackScheduled = true
        let becameActive = state == .idle
        if becameActive { state = .active }
        lock.unlock()
        replaced?.completion(.success(()))
        if becameActive { callbackQueue.async { self.stateChangedHandler?(.active) } }
        if schedule { callbackQueue.async { self.drainLatestCallback() } }
    }

    private func image(for frame: MediaFrame, version: UInt64) throws -> CGImage {
        conversionLock.lock()
        defer { conversionLock.unlock() }
        lock.lock()
        if imageVersion == version, let imageStorage { lock.unlock(); return imageStorage }
        lock.unlock()
        guard let buffer = extractPixelBuffer(frame) else { throw MediaCoreError.pixelBufferUnavailable }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr, let image else {
            throw MediaCoreError.pixelBufferUnavailable
        }
        lock.lock()
        convertedFrameCount += 1
        if lastFrameVersion == version { imageVersion = version; imageStorage = image }
        lock.unlock()
        return image
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
        updateState(.cancelled)
        deliveryFence.lock()
        deliveryFence.unlock()
        lock.lock()
        pendingFrame = nil
        let pending = pendingCallback
        pendingCallback = nil
        finishRequested = false
        let completions = finishCompletions
        finishCompletions.removeAll()
        lock.unlock()
        pending?.completion(.success(()))
        completions.forEach { $0(.success(())) }
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        if state == .finished || state == .cancelled {
            lock.unlock()
            completion(.success(()))
            return
        }
        pendingFrame = nil
        finishRequested = true
        let shouldFinishImmediately = isCallbackScheduled == false && pendingCallback == nil
        if shouldFinishImmediately {
            state = .finished
            finishRequested = false
        } else {
            finishCompletions.append(completion)
        }
        lock.unlock()
        if shouldFinishImmediately {
            callbackQueue.async { self.stateChangedHandler?(.finished) }
            completion(.success(()))
        }
    }

    private func drainLatestCallback() {
        lock.lock()
        let callback = (state == .finished || state == .cancelled) ? nil : pendingCallback
        pendingCallback = nil
        lock.unlock()
        if let callback {
            do {
                let image = handler == nil ? nil : try self.image(for: callback.frame, version: callback.version)
                deliveryFence.lock()
                lock.lock()
                let accepts = state != .cancelled && state != .finished && callback.version == lastFrameVersion
                lock.unlock()
                if accepts {
                    frameHandler?(callback.frame)
                    lock.lock()
                    let stillAccepts = state != .cancelled && state != .finished
                    lock.unlock()
                    if stillAccepts, let image { handler?(image, callback.frame.metadata) }
                }
                deliveryFence.unlock()
                callback.completion(.success(()))
            } catch { callback.completion(.failure(error)) }
        }
        lock.lock()
        let shouldFinish = finishRequested && pendingCallback == nil
        let shouldContinue = pendingCallback != nil && state != .finished && state != .cancelled
        var completions: [(Result<Void, Error>) -> Void] = []
        if shouldFinish {
            state = .finished
            finishRequested = false
            completions = finishCompletions
            finishCompletions.removeAll()
        }
        if !shouldContinue { isCallbackScheduled = false }
        lock.unlock()
        if shouldFinish {
            callbackQueue.async { self.stateChangedHandler?(.finished) }
            completions.forEach { $0(.success(())) }
        } else if shouldContinue {
            callbackQueue.async { self.drainLatestCallback() }
        }
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
