//
//  ProcessedPreviewSession.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import AVFoundation
import CoreVideo
import Foundation

#if canImport(UIKit) || os(macOS)
public struct ProcessedPreviewConfiguration: Sendable {
    public let preferredFramesPerSecond: Int

    public init(preferredFramesPerSecond: Int = 24) {
        self.preferredFramesPerSecond = min(max(preferredFramesPerSecond, 1), 60)
    }
}

public struct ProcessedPreviewRequest: @unchecked Sendable {
    public let player: AVPlayer
    public let plan: FrameProcessingPlan
    public let configuration: ProcessedPreviewConfiguration

    public init(
        player: AVPlayer,
        plan: FrameProcessingPlan,
        configuration: ProcessedPreviewConfiguration = .init()
    ) {
        self.player = player
        self.plan = plan
        self.configuration = configuration
    }
}

public enum ProcessedPreviewError: Error, Equatable {
    case pixelBufferUnavailable
}

public final class ProcessedPreviewSession: @unchecked Sendable {
    public typealias OutputHandler = (CVPixelBuffer, FrameMetadata, FrameProcessingPlan.Identity) -> Void

    public let player: AVPlayer
    public let planIdentity: FrameProcessingPlan.Identity
    public var errorHandler: ((Error) -> Void)?

    private let source: PlayerFrameSource
    private let consumer: LatestFrameProcessingConsumer

    public init(
        request: ProcessedPreviewRequest,
        callbackQueue: DispatchQueue = .main,
        output: @escaping OutputHandler
    ) throws {
        let processors = try request.plan.makeProcessors()
        player = request.player
        planIdentity = request.plan.identity
        source = PlayerFrameSource(
            player: request.player,
            preferredFramesPerSecond: request.configuration.preferredFramesPerSecond
        )
        consumer = LatestFrameProcessingConsumer(
            processors: processors,
            planIdentity: request.plan.identity,
            callbackQueue: callbackQueue,
            output: output
        )
        source.add(consumer: consumer)
        consumer.errorHandler = { [weak self] error in self?.errorHandler?(error) }
    }

    public func start() {
        consumer.start()
        source.start()
    }

    public func pause() {
        source.pause()
    }

    public func resume() {
        source.resume()
    }

    public func seek(to time: CMTime) {
        source.seek(to: time)
    }

    public func requestFrameUpdate() {
        source.requestFrameUpdate()
    }

    /// 非阻塞取消。尚未通过 delivery gate 的回调会被丢弃；已经进入用户闭包或当前处理器的工作可自然结束。
    public func cancel() {
        consumer.cancel()
        source.cancel()
    }
}

final class LatestFrameProcessingConsumer: MediaFrameConsumerNode, @unchecked Sendable {
    typealias OutputHandler = ProcessedPreviewSession.OutputHandler

    var errorHandler: ((Error) -> Void)?

    private let processors: [FrameProcessor]
    private let planIdentity: FrameProcessingPlan.Identity
    private let deliveryQueue: DispatchQueue
    private let output: OutputHandler
    private let lock = NSLock()
    private var isActive = false
    private var pendingFrame: MediaFrame?
    private var acceptsFrames = false
    private var generation: UInt64 = 0

    init(
        processors: [FrameProcessor],
        planIdentity: FrameProcessingPlan.Identity,
        callbackQueue: DispatchQueue,
        output: @escaping OutputHandler
    ) {
        self.processors = processors
        self.planIdentity = planIdentity
        deliveryQueue = DispatchQueue(
            label: "com.condy.kakapos.processed-preview.delivery",
            target: callbackQueue
        )
        self.output = output
    }

    func start() {
        lock.lock()
        generation &+= 1
        acceptsFrames = true
        pendingFrame = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        acceptsFrames = false
        pendingFrame = nil
        lock.unlock()
    }

    func consume(
        _ frame: MediaFrame,
        from source: MediaFrameSourceNode,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let work: (MediaFrame, UInt64)?
        lock.lock()
        if acceptsFrames == false {
            work = nil
        } else if isActive {
            pendingFrame = frame
            work = nil
        } else {
            isActive = true
            work = (frame, generation)
        }
        lock.unlock()
        completion(.success(()))
        if let work {
            process(work.0, at: 0, generation: work.1)
        }
    }

    private func process(_ frame: MediaFrame, at index: Int, generation: UInt64) {
        guard index < processors.count else {
            finish(frame, generation: generation)
            return
        }
        processors[index].process(frame) { [weak self] result in
            guard let self else { return }
            guard self.isCurrent(generation) else {
                self.processPendingFrame(after: generation)
                return
            }
            switch result {
            case let .success(processedFrame):
                self.process(processedFrame, at: index + 1, generation: generation)
            case let .failure(error):
                self.fail(error, generation: generation)
            }
        }
    }

    private func finish(_ frame: MediaFrame, generation: UInt64) {
        guard let pixelBuffer = extractPixelBuffer(frame) else {
            fail(ProcessedPreviewError.pixelBufferUnavailable, generation: generation)
            return
        }
        let delivery = PreviewFrameDelivery(
            pixelBuffer: pixelBuffer,
            metadata: frame.metadata,
            planIdentity: planIdentity,
            output: output
        )
        deliveryQueue.async { [weak self, delivery] in
            guard self?.isCurrent(generation) == true else { return }
            delivery.deliver()
        }
        processPendingFrame(after: generation)
    }

    private func fail(_ error: Error, generation: UInt64) {
        deliveryQueue.async { [weak self] in
            guard self?.isCurrent(generation) == true else { return }
            self?.errorHandler?(error)
        }
        processPendingFrame(after: generation)
    }

    private func isCurrent(_ candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return acceptsFrames && generation == candidate
    }

    private func processPendingFrame(after completedGeneration: UInt64) {
        let next: MediaFrame?
        lock.lock()
        if acceptsFrames, generation == completedGeneration {
            next = pendingFrame
            pendingFrame = nil
            isActive = next != nil
        } else {
            next = nil
            pendingFrame = nil
            isActive = false
        }
        lock.unlock()
        if let next {
            process(next, at: 0, generation: completedGeneration)
        }
    }
}

private struct PreviewFrameDelivery: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let metadata: FrameMetadata
    let planIdentity: FrameProcessingPlan.Identity
    let output: LatestFrameProcessingConsumer.OutputHandler

    func deliver() {
        output(pixelBuffer, metadata, planIdentity)
    }
}
#endif
