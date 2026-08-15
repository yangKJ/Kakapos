//
//  VideoPreviewProcessingLane.swift
//  Kakapos
//
//  Created by Condy on 2026/8/5.
//

import Foundation
import KakaposMediaCore

final class VideoPreviewProcessingLane: @unchecked Sendable {
    typealias Output = (
        MediaFrame,
        VideoPreviewGeneration,
        VideoPreviewModeIdentity
    ) -> Void

    let generation: VideoPreviewGeneration
    let identity: VideoPreviewModeIdentity
    var errorHandler: ((Error) -> Void)?
    var frameCompleted: ((TimeInterval) -> Void)?

    private let processors: [FrameProcessor]
    private let output: Output
    private let lock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.condy.kakapos.video-preview.processing", qos: .userInitiated)
    private let performanceAccumulator = VideoPreviewPerformanceAccumulator()
    private var acceptsFrames = true
    private var isProcessing = false
    private var pendingFrame: MediaFrame?
    private var currentOperation: FrameProcessingOperation?
    private var currentOperationToken: UInt64 = 0
    private var currentFrameStartedAt: UInt64?

    var performanceSnapshot: VideoPreviewPerformanceSnapshot {
        performanceAccumulator.snapshot
    }

    init(
        generation: VideoPreviewGeneration,
        mode: VideoPreviewMode,
        output: @escaping Output
    ) throws {
        self.generation = generation
        identity = mode.identity
        switch mode {
        case .original:
            processors = []
        case let .processed(plan):
            processors = try plan.makeProcessors()
        }
        self.output = output
    }

    func consume(_ frame: MediaFrame) {
        let replacesPending: Bool
        lock.lock()
        guard acceptsFrames else {
            lock.unlock()
            return
        }
        if isProcessing {
            replacesPending = pendingFrame != nil
            pendingFrame = frame
            lock.unlock()
            performanceAccumulator.recordSubmitted(frameIndex: frame.metadata.frameIndex, isPending: true, replacesPending: replacesPending)
            return
        }
        replacesPending = false
        isProcessing = true
        lock.unlock()
        performanceAccumulator.recordSubmitted(frameIndex: frame.metadata.frameIndex, isPending: false, replacesPending: replacesPending)
        begin(frame)
    }

    func cancel() {
        let operation: FrameProcessingOperation?
        let hadInFlightFrame: Bool
        lock.lock()
        acceptsFrames = false
        pendingFrame = nil
        operation = currentOperation
        currentOperation = nil
        currentOperationToken &+= 1
        hadInFlightFrame = isProcessing
        isProcessing = false
        lock.unlock()
        operation?.cancel()
        performanceAccumulator.markFinal(hadInFlightFrame: hadInFlightFrame)
    }

    private func begin(_ frame: MediaFrame) {
        lock.lock()
        currentFrameStartedAt = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
        performanceAccumulator.recordStarted()
        processingQueue.async { [weak self] in
            self?.process(frame, at: 0)
        }
    }

    private func process(_ frame: MediaFrame, at index: Int) {
        guard isCurrent else { return }
        guard index < processors.count else {
            finish(frame)
            return
        }
        let processor = processors[index]
        let operationToken = beginOperation()
        let operation = processFrame(using: processor, frame: frame) { [weak self] result in
            guard let self, self.isCurrent else { return }
            self.clearCurrentOperation(token: operationToken)
            switch result {
            case let .success(processedFrame):
                self.processingQueue.async { [weak self] in
                    self?.process(processedFrame, at: index + 1)
                }
            case let .failure(error):
                self.performanceAccumulator.recordFailure()
                self.errorHandler?(error)
                self.finishCurrentWork()
            }
        }
        installCurrentOperation(operation, token: operationToken)
    }

    private func finish(_ frame: MediaFrame) {
        guard isSupportedOutput(frame), isCurrent else {
            finishCurrentWork()
            return
        }
        output(frame, generation, identity)
        let duration = elapsedCurrentFrameDuration()
        performanceAccumulator.recordCompleted(duration: duration)
        frameCompleted?(duration)
        finishCurrentWork()
    }

    private func isSupportedOutput(_ frame: MediaFrame) -> Bool {
        if extractPixelBuffer(frame) != nil { return true }
        #if canImport(Metal)
        return extractTexture(frame) != nil
        #else
        return false
        #endif
    }

    private func finishCurrentWork() {
        let next: MediaFrame?
        lock.lock()
        currentOperation = nil
        currentFrameStartedAt = nil
        if acceptsFrames {
            next = pendingFrame
            pendingFrame = nil
            isProcessing = next != nil
        } else {
            next = nil
            pendingFrame = nil
            isProcessing = false
        }
        lock.unlock()
        if let next {
            begin(next)
        }
    }

    private func beginOperation() -> UInt64 {
        lock.lock()
        currentOperationToken &+= 1
        let token = currentOperationToken
        currentOperation = nil
        lock.unlock()
        return token
    }

    private func installCurrentOperation(_ operation: FrameProcessingOperation?, token: UInt64) {
        lock.lock()
        if acceptsFrames, currentOperationToken == token {
            currentOperation = operation
            lock.unlock()
        } else {
            lock.unlock()
            operation?.cancel()
        }
    }

    private func clearCurrentOperation(token: UInt64) {
        lock.lock()
        if currentOperationToken == token {
            currentOperation = nil
        }
        lock.unlock()
    }

    private func elapsedCurrentFrameDuration() -> TimeInterval {
        lock.lock()
        let startedAt = currentFrameStartedAt
        lock.unlock()
        guard let startedAt else { return 0 }
        let now = DispatchTime.now().uptimeNanoseconds
        return TimeInterval(now >= startedAt ? now - startedAt : 0) / 1_000_000_000
    }

    private var isCurrent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return acceptsFrames
    }
}
