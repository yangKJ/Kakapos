//
//  ImageSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import AVFoundation
import CoreGraphics
import CoreVideo

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct StillImageFrame {
    public var image: CGImage
    public var duration: CMTime
    public var transform: CGAffineTransform
    public var userInfo: [String: Any]

    public init(
        image: CGImage,
        duration: CMTime = CMTime(value: 1, timescale: 30),
        transform: CGAffineTransform = .identity,
        userInfo: [String: Any] = [:]
    ) {
        self.image = image
        self.duration = duration
        self.transform = transform
        self.userInfo = userInfo
    }
}

public final class ImageSource: MediaSource, MediaFrameSourceNode, MediaSourceSnapshotProviding, @unchecked Sendable {
    public enum MetadataKey {
        public static let imageIndex = "kakapos.image-source.index"
        public static let imageCount = "kakapos.image-source.count"
        public static let isLooping = "kakapos.image-source.looping"
    }

    public weak var delegate: MediaSourceDelegate?
    public var frames: [StillImageFrame] {
        get {
            pauseCondition.lock()
            let value = configuredFrames
            pauseCondition.unlock()
            return value
        }
        set {
            pauseCondition.lock()
            configuredFrames = newValue
            pauseCondition.unlock()
        }
    }
    public var renderSize: CGSize? {
        get {
            pauseCondition.lock()
            let value = configuredRenderSize
            pauseCondition.unlock()
            return value
        }
        set {
            pauseCondition.lock()
            configuredRenderSize = newValue
            pauseCondition.unlock()
        }
    }
    public var isLooping: Bool {
        get {
            pauseCondition.lock()
            let value = configuredIsLooping
            pauseCondition.unlock()
            return value
        }
        set {
            pauseCondition.lock()
            configuredIsLooping = newValue
            pauseCondition.unlock()
        }
    }
    public var callbackQueue: DispatchQueue {
        get {
            pauseCondition.lock()
            let value = configuredCallbackQueue
            pauseCondition.unlock()
            return value
        }
        set {
            pauseCondition.lock()
            configuredCallbackQueue = newValue
            pauseCondition.unlock()
        }
    }

    private let queue = DispatchQueue(label: "com.condy.kakapos.image-source")
    private let outputNode = MediaOutputNode()
    private let pauseCondition = NSCondition()
    private let deliveryFence = NSRecursiveLock()
    private var configuredFrames: [StillImageFrame]
    private var configuredRenderSize: CGSize?
    private var configuredIsLooping: Bool
    private var configuredCallbackQueue: DispatchQueue
    private var deliveryQueue: DispatchQueue?
    private var shouldStop = false
    private var isPaused = false
    private var isCancelled = false
    private var currentIndex = 0
    private var currentPresentationTime: CMTime = .zero
    private var generation: UInt64 = 0
    private var hasStarted = false
    private var isRunning = false
    private var didScheduleTerminalCallback = false
    private var inFlightFrames = 0
    private var peakInFlightFrames = 0
    private var failureDescription: String?
    private var cachedImageBytes = 0
    private var rasterizationCount = 0
    public let maximumInFlightFrameCount: Int
    public let imageCacheBudgetBytes: Int

    public var sourceSnapshot: MediaSourceSnapshot {
        pauseCondition.lock()
        defer { pauseCondition.unlock() }
        return MediaSourceSnapshot(stateDescription: failureDescription != nil ? "failed" : (isCancelled ? "cancelled" : (isRunning ? (isPaused ? "paused" : "reading") : (hasStarted ? "finished" : "idle"))),
            lastFrameIndex: nil, lastPresentationTime: nil, lastErrorDescription: failureDescription, details: [
                "inFlightFrames": String(inFlightFrames), "peakInFlightFrames": String(peakInFlightFrames),
                "maximumInFlightFrames": String(maximumInFlightFrameCount), "cachedImageBytes": String(cachedImageBytes),
                "rasterizationCount": String(rasterizationCount)
            ])
    }

    public init(
        frames: [StillImageFrame],
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main,
        maximumInFlightFrameCount: Int = 2,
        imageCacheBudgetBytes: Int = 32 * 1024 * 1024
    ) {
        self.maximumInFlightFrameCount = max(1, maximumInFlightFrameCount)
        self.imageCacheBudgetBytes = max(0, imageCacheBudgetBytes)
        configuredFrames = frames
        configuredRenderSize = renderSize
        configuredIsLooping = isLooping
        configuredCallbackQueue = callbackQueue
    }

    public convenience init(
        image: CGImage,
        duration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        callbackQueue: DispatchQueue = .main
    ) {
        self.init(
            frames: [StillImageFrame(image: image, duration: duration)],
            renderSize: renderSize,
            isLooping: false,
            callbackQueue: callbackQueue
        )
    }

    #if canImport(UIKit)
    public convenience init(
        images: [UIImage],
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main
    ) {
        let frames = images.compactMap { image -> StillImageFrame? in
            guard let cgImage = image.cgImage else { return nil }
            return StillImageFrame(image: cgImage, duration: frameDuration)
        }
        self.init(frames: frames, renderSize: renderSize, isLooping: isLooping, callbackQueue: callbackQueue)
    }
    #elseif canImport(AppKit)
    public convenience init(
        images: [NSImage],
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main
    ) {
        let frames = images.compactMap { image -> StillImageFrame? in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return StillImageFrame(image: cgImage, duration: frameDuration)
        }
        self.init(frames: frames, renderSize: renderSize, isLooping: isLooping, callbackQueue: callbackQueue)
    }
    #endif

    public func start() {
        pauseCondition.lock()
        guard hasStarted == false, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        hasStarted = true
        isRunning = true
        shouldStop = false
        isCancelled = false
        generation &+= 1
        let runGeneration = generation
        let run = RunConfiguration(
            frames: configuredFrames,
            renderSize: configuredRenderSize,
            isLooping: configuredIsLooping,
            deliveryQueue: makeDeliveryQueueIfNeeded()
        )
        pauseCondition.unlock()

        queue.async {
            guard !run.frames.isEmpty else {
                self.completeNaturally(expectedGeneration: runGeneration)
                return
            }
            self.consumeFrames(run, generation: runGeneration)
        }
    }

    public func pause() {
        pauseCondition.lock()
        if isRunning, shouldStop == false, isCancelled == false {
            isPaused = true
        }
        pauseCondition.unlock()
    }

    public func resume() {
        pauseCondition.lock()
        isPaused = false
        pauseCondition.broadcast()
        pauseCondition.unlock()
    }

    public func stop() {
        terminate(cancelled: false)
    }

    public func cancel() {
        terminate(cancelled: true)
    }

    private struct RunConfiguration {
        let frames: [StillImageFrame]
        let renderSize: CGSize?
        let isLooping: Bool
        let deliveryQueue: DispatchQueue
    }

    private func consumeFrames(_ run: RunConfiguration, generation expectedGeneration: UInt64) {
        let rasterizer = ImageSourceRasterizer()
        repeat {
            while currentIndex < run.frames.count && waitUntilReady(for: expectedGeneration) {

                let item = run.frames[currentIndex]
                do {
                    let pixelBuffer = try rasterizer.makeBuffer(image: item.image, size: run.renderSize,
                        budget: imageCacheBudgetBytes)
                    pauseCondition.lock()
                    guard isActiveRun(expectedGeneration) else { pauseCondition.unlock(); return }
                    inFlightFrames += 1
                    peakInFlightFrames = max(peakInFlightFrames, inFlightFrames)
                    cachedImageBytes = rasterizer.cachedBytes
                    rasterizationCount = rasterizer.rasterizationCount
                    pauseCondition.unlock()
                    let metadata = FrameMetadata(
                        presentationTime: currentPresentationTime,
                        duration: item.duration,
                        sourceTime: currentPresentationTime,
                        trackTransform: item.transform,
                        frameIndex: Int64(currentIndex),
                        userInfo: item.userInfo.merging([
                            MetadataKey.imageIndex: currentIndex,
                            MetadataKey.imageCount: run.frames.count,
                            MetadataKey.isLooping: run.isLooping
                        ]) { current, _ in current }
                    )
                    let frame = PixelBufferFrame(pixelBuffer: pixelBuffer, metadata: metadata)
                    run.deliveryQueue.async {
                        self.deliveryFence.lock()
                        defer { self.deliveryFence.unlock() }
                        guard self.canDeliverFrame(for: expectedGeneration) else {
                            self.acknowledgeFrame(expectedGeneration)
                            return
                        }
                        let group = DispatchGroup()
                        group.enter()
                        let acknowledgeDelegate = FrameProcessingCancellation { group.leave() }
                        if let delegate = self.delegate {
                            delegate.mediaSource(self, didOutput: frame) { _ in acknowledgeDelegate.cancel() }
                        } else { acknowledgeDelegate.cancel() }
                        group.enter()
                        let acknowledgeNode = FrameProcessingCancellation { group.leave() }
                        self.outputNode.transmit(frame, shouldContinue: { self.canDeliverFrame(for: expectedGeneration) }) { _ in
                            acknowledgeNode.cancel()
                        }
                        group.notify(queue: .global(qos: .userInitiated)) { self.acknowledgeFrame(expectedGeneration) }
                    }
                    currentPresentationTime = currentPresentationTime + item.duration
                    currentIndex += 1
                } catch {
                    finish(with: error, expectedGeneration: expectedGeneration)
                    return
                }
            }

            if run.isLooping && !run.frames.isEmpty && isRunActive(expectedGeneration) {
                currentIndex = 0
                continue
            }
            break
        } while true

        completeNaturally(expectedGeneration: expectedGeneration)
    }

    private func waitUntilReady(for expectedGeneration: UInt64) -> Bool {
        pauseCondition.lock()
        while (isPaused || inFlightFrames >= maximumInFlightFrameCount) && generation == expectedGeneration && !shouldStop && !isCancelled {
            pauseCondition.wait()
        }
        let isReady = isActiveRun(expectedGeneration)
        pauseCondition.unlock()
        return isReady
    }

    private func isActiveRun(_ expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration
            && isRunning
            && shouldStop == false
            && isCancelled == false
            && didScheduleTerminalCallback == false
    }

    private func isRunActive(_ expectedGeneration: UInt64) -> Bool {
        pauseCondition.lock()
        let isActive = isActiveRun(expectedGeneration)
        pauseCondition.unlock()
        return isActive
    }

    private func canDeliverFrame(for expectedGeneration: UInt64) -> Bool {
        pauseCondition.lock()
        let canDeliver = generation == expectedGeneration
        pauseCondition.unlock()
        return canDeliver
    }

    private func terminate(cancelled: Bool) {
        pauseCondition.lock()
        guard didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        inFlightFrames = 0
        cachedImageBytes = 0
        isCancelled = cancelled
        isRunning = false
        generation &+= 1
        didScheduleTerminalCallback = true
        let deliveryQueue = makeDeliveryQueueIfNeeded()
        pauseCondition.broadcast()
        pauseCondition.unlock()
        deliveryFence.lock()
        deliveryFence.unlock()
        deliveryQueue.async {
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private func finish(with error: Error, expectedGeneration: UInt64) {
        pauseCondition.lock()
        guard generation == expectedGeneration, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        failureDescription = error.localizedDescription
        inFlightFrames = 0
        cachedImageBytes = 0
        isRunning = false
        generation &+= 1
        didScheduleTerminalCallback = true
        let deliveryQueue = makeDeliveryQueueIfNeeded()
        pauseCondition.broadcast()
        pauseCondition.unlock()
        deliveryQueue.async {
            self.delegate?.mediaSource(self, didFail: error)
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private func completeNaturally(expectedGeneration: UInt64) {
        pauseCondition.lock()
        while inFlightFrames > 0 && generation == expectedGeneration && !shouldStop && !isCancelled { pauseCondition.wait() }
        guard generation == expectedGeneration, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        cachedImageBytes = 0
        isRunning = false
        didScheduleTerminalCallback = true
        let deliveryQueue = makeDeliveryQueueIfNeeded()
        pauseCondition.broadcast()
        pauseCondition.unlock()
        deliveryQueue.async {
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    /// Must be called while `pauseCondition` is locked.
    private func makeDeliveryQueueIfNeeded() -> DispatchQueue {
        if let deliveryQueue {
            return deliveryQueue
        }
        let queue = DispatchQueue(
            label: "com.condy.kakapos.image-source.delivery",
            target: configuredCallbackQueue
        )
        deliveryQueue = queue
        return queue
    }

    private func acknowledgeFrame(_ expectedGeneration: UInt64) {
        pauseCondition.lock()
        if generation == expectedGeneration { inFlightFrames = max(0, inFlightFrames - 1) }
        pauseCondition.broadcast()
        pauseCondition.unlock()
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    public func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }
}
