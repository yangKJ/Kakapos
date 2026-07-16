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
#endif

protocol PlayerFrameDriving: AnyObject {
    var configuration: PlayerFrameOutputDriver.Configuration { get set }
    var waitingForMediaDataHandler: ((CMTime) -> Void)? { get set }
    var mediaDataWillChangeHandler: (() -> Void)? { get set }
    func setNeedsUpdate()
    func updateIfNeeded()
}

private protocol PlayerFrameTicking: AnyObject {
    var preferredFramesPerSecond: Int { get set }
    var isPaused: Bool { get set }
    func invalidate()
}

private final class TickerHandlerTarget {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func tick() {
        handler()
    }
}

#if canImport(UIKit)
private final class DisplayLinkTicker: NSObject, PlayerFrameTicking {
    var preferredFramesPerSecond: Int {
        didSet {
            displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    var isPaused: Bool {
        get { displayLink.isPaused }
        set { displayLink.isPaused = newValue }
    }

    private let displayLink: CADisplayLink
    private let target: TickerHandlerTarget

    init(preferredFramesPerSecond: Int, handler: @escaping () -> Void) {
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.target = TickerHandlerTarget(handler: handler)
        self.displayLink = CADisplayLink(target: target, selector: #selector(TickerHandlerTarget.tick))
        super.init()
        self.displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        self.displayLink.add(to: .main, forMode: .common)
    }

    func invalidate() {
        displayLink.invalidate()
    }
}
#else
private final class DispatchTicker: PlayerFrameTicking {
    var preferredFramesPerSecond: Int {
        didSet {
            reschedule()
        }
    }

    var isPaused: Bool = true

    private let timer: DispatchSourceTimer
    private let target: TickerHandlerTarget

    init(preferredFramesPerSecond: Int, handler: @escaping () -> Void) {
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.target = TickerHandlerTarget(handler: handler)
        self.timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer.setEventHandler { [weak target] in
            target?.tick()
        }
        self.timer.resume()
        reschedule()
    }

    func invalidate() {
        timer.cancel()
    }

    private func reschedule() {
        let fps = max(preferredFramesPerSecond, 1)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000 / fps))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
    }
}
#endif

final class PlayerFrameOutputDriver: NSObject, @unchecked Sendable {

    struct Configuration {
        var sourcePixelBufferAttributes: [String: Any]?
        var preferredFramesPerSecond: Int = 30

        nonisolated(unsafe) static let `default` = Configuration()
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
            ticker?.preferredFramesPerSecond = configuration.preferredFramesPerSecond
        }
    }

    var waitingForMediaDataHandler: ((CMTime) -> Void)?
    var mediaDataWillChangeHandler: (() -> Void)?

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

    private var ticker: PlayerFrameTicking?
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
        ticker?.isPaused = false
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
        ticker?.invalidate()
        ticker = nil

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
        setupTicker()
    }

    private func setupTicker() {
        ticker?.invalidate()
        ticker = nil
        guard playerItemOutput != nil else { return }
        #if canImport(UIKit)
        ticker = DisplayLinkTicker(
            preferredFramesPerSecond: configuration.preferredFramesPerSecond,
            handler: { [weak self] in self?.handleTick() }
        )
        #else
        ticker = DispatchTicker(
            preferredFramesPerSecond: configuration.preferredFramesPerSecond,
            handler: { [weak self] in self?.handleTick() }
        )
        #endif
    }

    private func handleTick() {
        guard ticker?.isPaused == false || forceUpdate else { return }
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
            ticker?.isPaused = true
            waitingForMediaDataHandler?(requestTime)
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
        ticker?.isPaused = false
        mediaDataWillChangeHandler?()
    }
}

extension PlayerFrameOutputDriver: PlayerFrameDriving {}
