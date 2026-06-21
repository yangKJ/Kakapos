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

public final class PlayerFrameSource: NSObject, MediaSource {
    public enum MetadataKey {
        public static let playerItemTime = "kakapos.player-item-time"
        public static let playerRate = "kakapos.player-rate"
        public static let playbackState = "kakapos.playback-state"
        public static let generation = "kakapos.player-generation"
    }

    public weak var delegate: MediaSourceDelegate?
    public let player: AVPlayer
    public var preferredFramesPerSecond: Int {
        didSet {
            driver?.configuration.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    private var coordinator = PlayerFrameCoordinator()
    private var currentItemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeJumpObserver: NSObjectProtocol?
    private var driver: PlayerFrameOutputDriver?

    public init(player: AVPlayer, preferredFramesPerSecond: Int = 30) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        super.init()
    }

    deinit {
        invalidateObservers()
    }

    public func start() {
        observePlayerIfNeeded()
        _ = coordinator.start(with: player.currentItem)
        observeAttachedItem(player.currentItem)
        ensureDriver()
    }

    public func pause() {
        coordinator.pause()
    }

    public func resume() {
        coordinator.resume()
        driver?.setNeedsUpdate()
    }

    public func stop() {
        coordinator.stop()
        invalidateObservers()
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }

    private func ensureDriver() {
        if let driver {
            driver.configuration.preferredFramesPerSecond = preferredFramesPerSecond
            driver.setNeedsUpdate()
            return
        }

        let driver = PlayerFrameOutputDriver(
            player: player,
            configuration: .init(
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA],
                preferredFramesPerSecond: preferredFramesPerSecond
            )
        ) { [weak self] frame in
            self?.handleVideoFrame(frame)
        }
        self.driver = driver
    }

    private func handleVideoFrame(_ frame: PlayerFrameOutputDriver.VideoFrame) {
        guard coordinator.shouldDriveDisplayLink || player.rate == 0 else { return }
        let frameIndex = coordinator.markFrameOutput()
        let metadata = FrameMetadata(
            presentationTime: frame.presentationTimestamp,
            sourceTime: frame.playerTimestamp,
            trackTransform: frame.preferredTrackTransform,
            frameIndex: frameIndex,
            userInfo: [
                MetadataKey.playerItemTime: frame.requestTimestamp,
                MetadataKey.playerRate: player.rate,
                MetadataKey.playbackState: String(describing: coordinator.playbackState),
                MetadataKey.generation: coordinator.generation
            ]
        )
        delegate?.mediaSource(self, didOutput: MediaFrame(pixelBuffer: frame.pixelBuffer, metadata: metadata))
    }

    private func observePlayerIfNeeded() {
        guard currentItemObservation == nil else { return }
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, change in
            self?.handleCurrentItemChange(change.newValue ?? nil)
        }
    }

    private func handleCurrentItemChange(_ item: AVPlayerItem?) {
        let didChange = coordinator.updateCurrentItem(item)
        observeAttachedItem(item)
        if didChange {
            coordinator.resume()
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
            self.delegate?.mediaSourceDidFinish(self)
        }
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.coordinator.resume()
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
}
#endif
