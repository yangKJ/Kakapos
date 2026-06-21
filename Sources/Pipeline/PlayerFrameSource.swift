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
    public weak var delegate: MediaSourceDelegate?
    public let player: AVPlayer
    public var preferredFramesPerSecond: Int {
        didSet { displayLink?.preferredFramesPerSecond = preferredFramesPerSecond }
    }

    private var output: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var preferredTransform: CGAffineTransform = .identity
    private var frameIndex: Int64 = 0

    public init(player: AVPlayer, preferredFramesPerSecond: Int = 30) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        super.init()
    }

    public func start() {
        attachOutputIfNeeded()
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    public func pause() {
        displayLink?.isPaused = true
    }

    public func resume() {
        displayLink?.isPaused = false
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }

    @objc private func tick() {
        guard let output = output else { return }
        let requestTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: requestTime) else { return }
        var presentationTime = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: requestTime, itemTimeForDisplay: &presentationTime) else { return }
        frameIndex += 1
        let metadata = FrameMetadata(
            presentationTime: presentationTime,
            sourceTime: player.currentTime(),
            trackTransform: preferredTransform,
            frameIndex: frameIndex
        )
        delegate?.mediaSource(self, didOutput: MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata))
    }

    private func attachOutputIfNeeded() {
        guard output == nil, let item = player.currentItem else { return }
        if let track = item.asset.tracks(withMediaType: .video).first {
            preferredTransform = track.preferredTransform
        }
        let attributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        self.output = output
    }
}
#endif
