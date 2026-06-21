//
//  PlayerFrameSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

#if canImport(UIKit)
import UIKit

public final class PlayerFrameSource: NSObject, MediaSource, MediaFrameSourceNode {
    public struct Summary {
        public let state: State
        public let generation: Int64
        public let frameIndex: Int64
        public let hasLastFrame: Bool
        public let hasSeekTarget: Bool
        public let preferredFramesPerSecond: Int

        public var summaryText: String {
            "state \(state) · generation \(generation) · frame \(frameIndex) · lastFrame \(hasLastFrame ? "yes" : "no") · seekTarget \(hasSeekTarget ? "yes" : "no") · fps \(preferredFramesPerSecond)"
        }
    }

    public enum State: Equatable {
        case idle
        case active
        case paused
        case waitingForMediaData
        case finished
    }

    public enum MetadataKey {
        public static let playerItemTime = "kakapos.player-item-time"
        public static let playerRate = "kakapos.player-rate"
        public static let playbackState = "kakapos.playback-state"
        public static let generation = "kakapos.player-generation"
        public static let frameRequestReason = "kakapos.player-frame-request-reason"
        public static let seekTargetTime = "kakapos.player-seek-target-time"
    }

    public weak var delegate: MediaSourceDelegate?
    public let player: AVPlayer
    public private(set) var state: State = .idle
    public private(set) var lastFrame: MediaFrame?
    public private(set) var lastSeekTargetTime: CMTime?
    public var frameHandler: ((MediaFrame) -> Void)?
    public var stateChangedHandler: ((State) -> Void)?
    public var itemChangedHandler: ((AVPlayerItem?) -> Void)?
    public var preferredFramesPerSecond: Int {
        didSet {
            driver?.configuration.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    public var summary: Summary {
        Summary(
            state: state,
            generation: coordinator.generation,
            frameIndex: coordinator.frameIndex,
            hasLastFrame: lastFrame != nil,
            hasSeekTarget: lastSeekTargetTime != nil,
            preferredFramesPerSecond: preferredFramesPerSecond
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    private var coordinator = PlayerFrameCoordinator()
    private var currentItemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeJumpObserver: NSObjectProtocol?
    private var driver: PlayerFrameDriving?
    private let outputNode = MediaOutputNode()
    private let driverFactory: (AVPlayer, PlayerFrameOutputDriver.Configuration, @escaping (PlayerFrameOutputDriver.VideoFrame) -> Void) -> PlayerFrameDriving

    public init(player: AVPlayer, preferredFramesPerSecond: Int = 30) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.driverFactory = { player, configuration, handler in
            PlayerFrameOutputDriver(player: player, configuration: configuration, handler: handler)
        }
        super.init()
    }

    init(
        player: AVPlayer,
        preferredFramesPerSecond: Int = 30,
        driverFactory: @escaping (AVPlayer, PlayerFrameOutputDriver.Configuration, @escaping (PlayerFrameOutputDriver.VideoFrame) -> Void) -> PlayerFrameDriving
    ) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.driverFactory = driverFactory
        super.init()
    }

    deinit {
        invalidateObservers()
    }

    public func start() {
        observePlayerIfNeeded()
        lastSeekTargetTime = nil
        lastFrame = nil
        _ = coordinator.start(with: player.currentItem)
        updateState(from: coordinator.playbackState)
        observeAttachedItem(player.currentItem)
        ensureDriver()
        driver?.setNeedsUpdate()
    }

    public func pause() {
        coordinator.pause()
        updateState(from: coordinator.playbackState)
    }

    public func resume() {
        coordinator.resume()
        updateState(from: coordinator.playbackState)
        driver?.setNeedsUpdate()
    }

    public func stop() {
        coordinator.stop()
        updateState(from: coordinator.playbackState)
        lastSeekTargetTime = nil
        invalidateObservers()
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }

    public func requestFrameUpdate() {
        driver?.setNeedsUpdate()
    }

    public func refreshCurrentFrameIfNeeded() {
        driver?.updateIfNeeded()
    }

    public func seek(
        to time: CMTime,
        toleranceBefore: CMTime = .zero,
        toleranceAfter: CMTime = .zero,
        completion: ((Bool) -> Void)? = nil
    ) {
        lastSeekTargetTime = time
        lastFrame = nil
        player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] finished in
            guard let self else {
                completion?(finished)
                return
            }
            if finished {
                self.coordinator.resume()
                self.updateState(from: self.coordinator.playbackState)
                self.driver?.setNeedsUpdate()
                self.driver?.updateIfNeeded()
            }
            completion?(finished)
        }
    }

    private func ensureDriver() {
        if let driver {
            driver.configuration.preferredFramesPerSecond = preferredFramesPerSecond
            driver.setNeedsUpdate()
            return
        }

        let configuration = PlayerFrameOutputDriver.Configuration(
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA],
            preferredFramesPerSecond: preferredFramesPerSecond
        )
        let driver = driverFactory(player, configuration) { [weak self] frame in
            self?.handleVideoFrame(frame)
        }
        driver.waitingForMediaDataHandler = { [weak self] _ in
            guard let self else { return }
            if self.coordinator.beginWaitingForMediaData() {
                self.updateState(from: self.coordinator.playbackState)
            }
        }
        driver.mediaDataWillChangeHandler = { [weak self] in
            guard let self else { return }
            if self.coordinator.mediaDataWillChange() {
                self.updateState(from: self.coordinator.playbackState)
            }
        }
        self.driver = driver
    }

    private func handleVideoFrame(_ frame: PlayerFrameOutputDriver.VideoFrame) {
        guard coordinator.shouldDriveDisplayLink || player.rate == 0 else { return }
        let frameIndex = coordinator.markFrameOutput()
        updateState(from: coordinator.playbackState)
        let seekTargetTime = lastSeekTargetTime
        var userInfo: [String: Any] = [
            MetadataKey.playerItemTime: frame.requestTimestamp,
            MetadataKey.playerRate: player.rate,
            MetadataKey.playbackState: String(describing: coordinator.playbackState),
            MetadataKey.generation: coordinator.generation
        ]
        if let seekTargetTime {
            userInfo[MetadataKey.seekTargetTime] = seekTargetTime
            userInfo[MetadataKey.frameRequestReason] = "seek"
            lastSeekTargetTime = nil
        } else if player.rate == 0 {
            userInfo[MetadataKey.frameRequestReason] = "manual"
        } else {
            userInfo[MetadataKey.frameRequestReason] = "playback"
        }
        let metadata = FrameMetadata(
            presentationTime: frame.presentationTimestamp,
            sourceTime: frame.playerTimestamp,
            trackTransform: frame.preferredTrackTransform,
            frameIndex: frameIndex,
            userInfo: userInfo
        )
        let mediaFrame = MediaFrame(pixelBuffer: frame.pixelBuffer, metadata: metadata)
        lastFrame = mediaFrame
        frameHandler?(mediaFrame)
        delegate?.mediaSource(self, didOutput: mediaFrame)
        outputNode.transmit(mediaFrame) { _ in }
    }

    private func observePlayerIfNeeded() {
        guard currentItemObservation == nil else { return }
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, change in
            self?.handleCurrentItemChange(change.newValue ?? nil)
        }
    }

    private func handleCurrentItemChange(_ item: AVPlayerItem?) {
        let didChange = coordinator.updateCurrentItem(item)
        if didChange {
            lastSeekTargetTime = nil
            lastFrame = nil
        }
        itemChangedHandler?(item)
        observeAttachedItem(item)
        if didChange {
            coordinator.resume()
            updateState(from: coordinator.playbackState)
            driver?.setNeedsUpdate()
        }
    }

    private func observeAttachedItem(_ item: AVPlayerItem?) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        guard let item else { return }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.coordinator.stop()
            self.updateState(from: self.coordinator.playbackState)
            self.delegate?.mediaSourceDidFinish(self)
        }
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.coordinator.resume()
            self.updateState(from: self.coordinator.playbackState)
            self.driver?.setNeedsUpdate()
        }
    }

    private func invalidateObservers() {
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        driver = nil
    }

    private func updateState(from playbackState: PlayerFramePlaybackState) {
        let nextState: State
        switch playbackState {
        case .idle:
            nextState = .idle
        case .running:
            nextState = .active
        case .paused:
            nextState = .paused
        case .waitingForMediaData:
            nextState = .waitingForMediaData
        case .finished:
            nextState = .finished
        }
        guard state != nextState else { return }
        state = nextState
        stateChangedHandler?(nextState)
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
#endif
