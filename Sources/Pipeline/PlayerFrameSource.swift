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
        didSet { displayLink?.preferredFramesPerSecond = preferredFramesPerSecond }
    }

    private let outputQueue = DispatchQueue(label: "com.condy.kakapos.player-frame-source.output")
    private var attachedItem: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var currentItemObservation: NSKeyValueObservation?
    private var currentStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeJumpObserver: NSObjectProtocol?
    private var preferredTransform: CGAffineTransform = .identity
    private var coordinator = PlayerFrameCoordinator()
    private var needsForcedUpdate = false

    public init(player: AVPlayer, preferredFramesPerSecond: Int = 30) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        super.init()
    }

    deinit {
        detachCurrentOutput()
        invalidateObservers()
        displayLink?.invalidate()
    }

    public func start() {
        observePlayerIfNeeded()
        _ = coordinator.start(with: player.currentItem)
        observeAttachedItem(player.currentItem)
        ensureDisplayLink()
        updateDisplayLinkState()
    }

    public func pause() {
        coordinator.pause()
        updateDisplayLinkState()
    }

    public func resume() {
        coordinator.resume()
        setNeedsUpdate()
        updateDisplayLinkState()
    }

    public func stop() {
        coordinator.stop()
        displayLink?.invalidate()
        displayLink = nil
        detachCurrentOutput()
        invalidateObservers()
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }

    @objc private func tick() {
        guard coordinator.shouldDriveDisplayLink,
              let output,
              let item = player.currentItem,
              item.status == .readyToPlay else { return }

        updateIfNeeded(for: item, output: output)
    }

    private func updateIfNeeded(for item: AVPlayerItem, output: AVPlayerItemVideoOutput, force: Bool = false) {
        var requestTime = item.currentTime()
        if !force {
            requestTime = output.itemTime(forHostTime: CACurrentMediaTime())
        }
        guard requestTime >= .zero else { return }

        let shouldCopy = force || needsForcedUpdate || output.hasNewPixelBuffer(forItemTime: requestTime)
        guard shouldCopy else {
            guard player.timeControlStatus != .paused else { return }
            if coordinator.beginWaitingForMediaData() {
                output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
                updateDisplayLinkState()
            }
            return
        }

        var presentationTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: requestTime, itemTimeForDisplay: &presentationTime) else { return }
        needsForcedUpdate = false
        let frameIndex = coordinator.markFrameOutput()
        let metadata = FrameMetadata(
            presentationTime: presentationTime,
            sourceTime: player.currentTime(),
            trackTransform: preferredTransform,
            frameIndex: frameIndex,
            userInfo: [
                MetadataKey.playerItemTime: requestTime,
                MetadataKey.playerRate: player.rate,
                MetadataKey.playbackState: String(describing: coordinator.playbackState),
                MetadataKey.generation: coordinator.generation
            ]
        )
        delegate?.mediaSource(self, didOutput: MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata))
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
            setNeedsUpdate()
        }
        updateDisplayLinkState()
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func updateDisplayLinkState() {
        displayLink?.isPaused = !coordinator.shouldDriveDisplayLink
    }

    private func observeAttachedItem(_ item: AVPlayerItem?) {
        detachCurrentOutput()
        attachedItem = item
        guard let item else { return }

        currentStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
            self?.handleItemStatus(currentItem.status, for: currentItem)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.player.currentItem === item else { return }
            self.coordinator.stop()
            self.updateDisplayLinkState()
            self.delegate?.mediaSourceDidFinish(self)
        }
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleTimeJumped()
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, for item: AVPlayerItem) {
        switch status {
        case .readyToPlay:
            handleReadyToPlay(for: item)
            coordinator.resume()
            setNeedsUpdate()
            updateDisplayLinkState()
        case .failed:
            let error = item.error ?? VideoX.Error.unknown
            delegate?.mediaSource(self, didFail: error)
        default:
            break
        }
    }

    private func handleReadyToPlay(for item: AVPlayerItem) {
        guard attachedItem === item else { return }
        preferredTransform = item.asset.tracks(withMediaType: .video).first?.preferredTransform ?? .identity
        guard output == nil else { return }
        let attributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        output.setDelegate(self, queue: outputQueue)
        item.add(output)
        self.output = output
    }

    private func handleTimeJumped() {
        coordinator.resume()
        setNeedsUpdate()
        updateDisplayLinkState()
    }

    private func setNeedsUpdate() {
        needsForcedUpdate = true
        guard let item = attachedItem, let output else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateIfNeeded(for: item, output: output, force: true)
        }
    }

    private func detachCurrentOutput() {
        currentStatusObservation?.invalidate()
        currentStatusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        if let output, let attachedItem {
            attachedItem.remove(output)
        }
        attachedItem = nil
        output = nil
    }

    private func invalidateObservers() {
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        currentStatusObservation?.invalidate()
        currentStatusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
    }
}

extension PlayerFrameSource: AVPlayerItemOutputPullDelegate {
    public func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        guard coordinator.mediaDataWillChange() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateDisplayLinkState()
        }
    }

    public func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        coordinator.resume()
        setNeedsUpdate()
        DispatchQueue.main.async { [weak self] in
            self?.updateDisplayLinkState()
        }
    }
}
#endif
