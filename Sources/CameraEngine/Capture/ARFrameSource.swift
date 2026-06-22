//
//  ARFrameSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

#if canImport(ARKit) && (os(iOS) || os(visionOS))
import ARKit

@available(iOS 13.0, *)
public final class ARFrameSource: NSObject, MediaSource {
    public struct Snapshot: Equatable {
        public let isRunning: Bool
        public let frameCount: Int64
        public let lastPresentationTime: CMTime?
    }

    public struct Summary {
        public let isRunning: Bool
        public let frameCount: Int64
        public let lastPresentationTime: CMTime?

        public var summaryText: String {
            var text = "running \(isRunning ? "yes" : "no") · frames \(frameCount)"
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            return text
        }
    }

    public weak var delegate: MediaSourceDelegate?
    public let session: ARSession
    public var frameHandler: ((MediaFrame) -> Void)?
    public private(set) var isRunning = false
    public private(set) var frameCount: Int64 = 0
    public private(set) var lastPresentationTime: CMTime?

    public var snapshot: Snapshot {
        Snapshot(isRunning: isRunning, frameCount: frameCount, lastPresentationTime: lastPresentationTime)
    }

    public var summary: Summary {
        Summary(isRunning: isRunning, frameCount: frameCount, lastPresentationTime: lastPresentationTime)
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(session: ARSession = ARSession()) {
        self.session = session
        super.init()
        self.session.delegate = self
    }

    public func start() {
        isRunning = true
    }

    public func pause() {
        isRunning = false
    }

    public func resume() {
        isRunning = true
    }

    public func stop() {
        isRunning = false
        frameCount = 0
        lastPresentationTime = nil
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }
}

@available(iOS 13.0, *)
extension ARFrameSource: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        frameCount += 1
        lastPresentationTime = timestamp
        let mediaFrame = MediaFrame(
            pixelBuffer: frame.capturedImage,
            metadata: FrameMetadata(
                presentationTime: timestamp,
                sourceTime: timestamp,
                frameIndex: frameCount - 1,
                userInfo: ["kakapos.camera.ar-frame": true]
            )
        )
        frameHandler?(mediaFrame)
        delegate?.mediaSource(self, didOutput: mediaFrame)
    }
}
#endif
