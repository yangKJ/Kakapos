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
    public weak var delegate: MediaSourceDelegate?
    public let session: ARSession
    public var frameHandler: ((MediaFrame) -> Void)?
    public private(set) var isRunning = false

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
        let mediaFrame = MediaFrame(
            pixelBuffer: frame.capturedImage,
            metadata: FrameMetadata(
                presentationTime: timestamp,
                sourceTime: timestamp,
                userInfo: ["kakapos.camera.ar-frame": true]
            )
        )
        frameHandler?(mediaFrame)
        delegate?.mediaSource(self, didOutput: mediaFrame)
    }
}
#endif
