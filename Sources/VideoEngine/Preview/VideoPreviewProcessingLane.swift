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

    private let processors: [FrameProcessor]
    private let output: Output
    private let lock = NSLock()
    private var acceptsFrames = true
    private var isProcessing = false
    private var pendingFrame: MediaFrame?

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
        lock.lock()
        guard acceptsFrames else {
            lock.unlock()
            return
        }
        if isProcessing {
            pendingFrame = frame
            lock.unlock()
            return
        }
        isProcessing = true
        lock.unlock()
        process(frame, at: 0)
    }

    func cancel() {
        lock.lock()
        acceptsFrames = false
        pendingFrame = nil
        lock.unlock()
    }

    private func process(_ frame: MediaFrame, at index: Int) {
        guard isCurrent else { return }
        guard index < processors.count else {
            finish(frame)
            return
        }
        processors[index].process(frame) { [weak self] result in
            guard let self, self.isCurrent else { return }
            switch result {
            case let .success(processedFrame):
                self.process(processedFrame, at: index + 1)
            case let .failure(error):
                self.errorHandler?(error)
                self.finishCurrentWork()
            }
        }
    }

    private func finish(_ frame: MediaFrame) {
        guard isSupportedOutput(frame), isCurrent else {
            finishCurrentWork()
            return
        }
        output(frame, generation, identity)
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
            process(next, at: 0)
        }
    }

    private var isCurrent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return acceptsFrames
    }
}
