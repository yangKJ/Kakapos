//
//  VideoPreviewSession.swift
//  Kakapos
//
//  Created by Condy on 2026/8/5.
//

#if canImport(UIKit)
import AVFoundation
import Foundation
import KakaposMediaCore

/// 单 AVPlayer、单 PlayerFrameSource、单 Metal Surface 的视频预览会话。
/// 播放、暂停、Seek、音量与 currentItem 的 authority 始终属于宿主。
public final class VideoPreviewSession: @unchecked Sendable {
    public let player: AVPlayer
    public let surface: VideoPreviewSurface
    public var readinessHandler: ((VideoPreviewReadiness) -> Void)?
    public var errorHandler: ((Error) -> Void)?

    private let source: PlayerFrameSource
    private let stateLock = NSLock()
    private let modeSwitchLock = NSLock()
    private var generationRawValue: UInt64 = 0
    private var lane: VideoPreviewProcessingLane?
    private var reportedReadyGeneration: VideoPreviewGeneration?
    private var isCancelled = false
    private var isStarted = false

    public init(
        player: AVPlayer,
        surface: VideoPreviewSurface,
        configuration: VideoPreviewConfiguration = .init()
    ) {
        self.player = player
        self.surface = surface
        source = PlayerFrameSource(
            player: player,
            preferredFramesPerSecond: configuration.preferredFramesPerSecond,
            suppressesPlayerRendering: true
        )
        source.frameHandler = { [weak self] frame in
            self?.currentLane()?.consume(frame)
        }
        surface.framePresented = { [weak self] generation, identity, time in
            guard let self,
                  self.claimFirstReady(generation: generation, identity: identity) else { return }
            self.readinessHandler?(.ready(
                generation: generation,
                identity: identity,
                presentationTime: time
            ))
        }
        surface.framePresentationFailed = { [weak self] generation, identity in
            guard let self, self.accepts(generation: generation, identity: identity) else { return }
            self.readinessHandler?(.failed(generation: generation, identity: identity))
        }
        _ = try? setMode(.original)
    }

    deinit {
        cancel()
    }

    public func start() {
        stateLock.lock()
        guard !isCancelled, !isStarted else {
            stateLock.unlock()
            return
        }
        isStarted = true
        stateLock.unlock()
        source.start()
        source.requestFrameUpdate()
    }

    @discardableResult
    public func setMode(_ mode: VideoPreviewMode) throws -> VideoPreviewGeneration {
        modeSwitchLock.lock()
        defer { modeSwitchLock.unlock() }
        stateLock.lock()
        if let lane, lane.identity == mode.identity, !isCancelled {
            let generation = lane.generation
            stateLock.unlock()
            return generation
        }
        let nextRawValue = generationRawValue &+ 1
        stateLock.unlock()

        let generation = VideoPreviewGeneration(rawValue: nextRawValue)
        let nextLane = try VideoPreviewProcessingLane(
            generation: generation,
            mode: mode
        ) { [weak self] pixelBuffer, metadata, generation, identity in
            guard let self, self.accepts(generation: generation, identity: identity) else { return }
            self.surface.submit(
                pixelBuffer: pixelBuffer,
                metadata: metadata,
                generation: generation,
                identity: identity
            )
        }
        nextLane.errorHandler = { [weak self, weak nextLane] error in
            guard let self, let nextLane,
                  self.accepts(generation: nextLane.generation, identity: nextLane.identity) else { return }
            self.readinessHandler?(.failed(
                generation: nextLane.generation,
                identity: nextLane.identity
            ))
            self.errorHandler?(error)
        }

        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            nextLane.cancel()
            return generation
        }
        generationRawValue = nextRawValue
        let previousLane = lane
        lane = nextLane
        reportedReadyGeneration = nil
        let isStarted = self.isStarted
        stateLock.unlock()
        previousLane?.cancel()
        surface.awaitFirstFrame(generation: generation, identity: mode.identity)
        readinessHandler?(.awaitingFirstFrame(generation: generation, identity: mode.identity))
        if let lastFrame = source.lastFrame {
            nextLane.consume(lastFrame)
        }
        if isStarted {
            source.requestFrameUpdate()
        }
        return generation
    }

    public func setPresentationActive(_ active: Bool) {
        guard !isCancelled else { return }
        if active {
            source.resume()
            source.requestFrameUpdate()
        } else {
            source.pause()
        }
    }

    public func requestCurrentFrame() {
        guard !isCancelled else { return }
        if let lastFrame = source.lastFrame {
            currentLane()?.consume(lastFrame)
        }
        source.requestFrameUpdate()
    }

    public func cancel() {
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            return
        }
        isCancelled = true
        let lane = self.lane
        self.lane = nil
        reportedReadyGeneration = nil
        stateLock.unlock()
        lane?.cancel()
        source.cancel()
        surface.cancelPresentation()
        readinessHandler?(.cancelled)
    }

    private func currentLane() -> VideoPreviewProcessingLane? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled ? nil : lane
    }

    private func accepts(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !isCancelled
            && lane?.generation == generation
            && lane?.identity == identity
    }

    private func claimFirstReady(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isCancelled,
              lane?.generation == generation,
              lane?.identity == identity,
              reportedReadyGeneration != generation else { return false }
        reportedReadyGeneration = generation
        return true
    }
}
#endif
