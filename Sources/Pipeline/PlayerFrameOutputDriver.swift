//
//  PlayerFrameOutputDriver.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

#if canImport(UIKit)
import UIKit

final class PlayerFrameOutputDriver: NSObject {

    struct Configuration {
        var sourcePixelBufferAttributes: [String: Any]?
        var preferredFramesPerSecond: Int = 30

        static let `default` = Configuration()
    }

    struct VideoFrame {
        let preferredTrackTransform: CGAffineTransform
        let presentationTimestamp: CMTime
        let playerTimestamp: CMTime
        let requestTimestamp: CMTime
        let pixelBuffer: CVPixelBuffer
    }

    var configuration = Configuration() {
        didSet {
            displayLink?.preferredFramesPerSecond = configuration.preferredFramesPerSecond
        }
    }

    private(set) var player: AVPlayer? {
        willSet {
            if newValue !== player {
                detachCurrentPlayer()
            }
        }
        didSet {
            if player !== oldValue {
                attachCurrentPlayer()
            }
        }
    }

    private var displayLink: CADisplayLink?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemObservation: NSKeyValueObservation?
    private var playerItem: AVPlayerItem?
    private var playerItemOutput: AVPlayerItemVideoOutput?
    private var preferredVideoTransform: CGAffineTransform = .identity
    private var forceUpdate = false
    private let advanceInterval: TimeInterval = 1.0 / 60.0
    private let handler: (VideoFrame) -> Void

    init(
        player: AVPlayer,
        configuration: Configuration = .default,
        handler: @escaping (VideoFrame) -> Void
    ) {
        self.configuration = configuration
        self.handler = handler
        self.player = player
        super.init()
        attachCurrentPlayer()
    }

    deinit {
        detachCurrentPlayer()
    }

    func setNeedsUpdate() {
        displayLink?.isPaused = false
        forceUpdate = true
    }

    func updateIfNeeded() {
        if forceUpdate {
            update(forced: true)
            forceUpdate = false
        }
    }

    private func detachCurrentPlayer() {
        updatePlayerItem(nil)
        playerItemObservation?.invalidate()
        playerItemObservation = nil
    }

    private func attachCurrentPlayer() {
        playerItemObservation = player?.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            guard let self, self.player === player else { return }
            self.updatePlayerItem(player.currentItem)
        }
    }

    private func updatePlayerItem(_ playerItem: AVPlayerItem?) {
        displayLink?.invalidate()
        displayLink = nil

        if let output = playerItemOutput, let playerItem, playerItem.outputs.contains(output) {
            playerItem.remove(output)
        }
        playerItemOutput = nil
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil

        self.playerItem = playerItem
        playerItemStatusObservation = self.playerItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self, self.playerItem === item, item.status == .readyToPlay else { return }
            self.handleReadyToPlay()
        }
    }

    private func handleReadyToPlay() {
        guard let player, let playerItem else { return }
        _ = player

        guard let videoTrack = playerItem.asset.tracks(withMediaType: .video).first else {
            return
        }
        preferredVideoTransform = videoTrack.preferredTransform

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: configuration.sourcePixelBufferAttributes)
        output.setDelegate(self, queue: .main)
        playerItem.add(output)
        playerItemOutput = output
        setupDisplayLink()
    }

    private func setupDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil

        guard playerItemOutput != nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkUpdate(_:)))
        displayLink.preferredFramesPerSecond = configuration.preferredFramesPerSecond
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc
    private func handleDisplayLinkUpdate(_ sender: CADisplayLink) {
        guard let player else { return }
        if player.rate != 0 {
            forceUpdate = true
        }
        update(forced: forceUpdate)
        forceUpdate = false
    }

    private func update(forced: Bool) {
        guard let output = playerItemOutput, let player else { return }

        let requestTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard requestTime >= .zero else { return }

        if !forced && !output.hasNewPixelBuffer(forItemTime: requestTime) {
            displayLink?.isPaused = true
            output.requestNotificationOfMediaDataChange(withAdvanceInterval: advanceInterval)
            return
        }

        var presentationTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: requestTime, itemTimeForDisplay: &presentationTime) else {
            return
        }
        handler(
            VideoFrame(
                preferredTrackTransform: preferredVideoTransform,
                presentationTimestamp: presentationTime,
                playerTimestamp: player.currentTime(),
                requestTimestamp: requestTime,
                pixelBuffer: pixelBuffer
            )
        )
    }
}

extension PlayerFrameOutputDriver: AVPlayerItemOutputPullDelegate {
    func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        displayLink?.isPaused = false
    }
}
#endif
