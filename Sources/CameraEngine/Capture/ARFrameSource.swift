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
    public struct Configuration {
        public let runHandler: ((ARSession) -> Void)?
        public let pauseHandler: ((ARSession) -> Void)?
        public let stopHandler: ((ARSession) -> Void)?
        public let includesAudio: Bool

        public init(
            runHandler: ((ARSession) -> Void)? = nil,
            pauseHandler: ((ARSession) -> Void)? = nil,
            stopHandler: ((ARSession) -> Void)? = nil,
            includesAudio: Bool = false
        ) {
            self.runHandler = runHandler
            self.pauseHandler = pauseHandler
            self.stopHandler = stopHandler
            self.includesAudio = includesAudio
        }
    }

    public struct Snapshot: Equatable {
        public let isSupported: Bool
        public let isRunning: Bool
        public let includesAudio: Bool
        public let frameCount: Int64
        public let lastPresentationTime: CMTime?
        public let advancedEventCount: Int
        public let latestAdvancedEventSummaryText: String
    }

    public struct Summary {
        public let isSupported: Bool
        public let isRunning: Bool
        public let includesAudio: Bool
        public let frameCount: Int64
        public let lastPresentationTime: CMTime?
        public let advancedEventCount: Int
        public let latestAdvancedEventSummaryText: String

        public var summaryText: String {
            var text = "supported \(isSupported ? "yes" : "no") · running \(isRunning ? "yes" : "no") · audio \(includesAudio ? "yes" : "no") · frames \(frameCount)"
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            text += " · events \(advancedEventCount) · latest \(latestAdvancedEventSummaryText)"
            return text
        }
    }

    public weak var delegate: MediaSourceDelegate?
    public let session: ARSession
    public let configuration: Configuration
    public let advancedOutput = CameraAdvancedOutput()
    public var frameHandler: ((MediaFrame) -> Void)?
    public private(set) var isRunning = false
    public private(set) var frameCount: Int64 = 0
    public private(set) var lastPresentationTime: CMTime?

    public static var isSupported: Bool { true }

    public var snapshot: Snapshot {
        Snapshot(
            isSupported: Self.isSupported,
            isRunning: isRunning,
            includesAudio: configuration.includesAudio,
            frameCount: frameCount,
            lastPresentationTime: lastPresentationTime,
            advancedEventCount: advancedOutput.eventCount,
            latestAdvancedEventSummaryText: advancedOutput.latestEventSummaryText
        )
    }

    public var summary: Summary {
        Summary(
            isSupported: Self.isSupported,
            isRunning: isRunning,
            includesAudio: configuration.includesAudio,
            frameCount: frameCount,
            lastPresentationTime: lastPresentationTime,
            advancedEventCount: advancedOutput.eventCount,
            latestAdvancedEventSummaryText: advancedOutput.latestEventSummaryText
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(session: ARSession = ARSession(), configuration: Configuration = .init()) {
        self.session = session
        self.configuration = configuration
        super.init()
        self.session.delegate = self
    }

    public func start() {
        isRunning = true
        configuration.runHandler?(session)
    }

    public func pause() {
        isRunning = false
        configuration.pauseHandler?(session)
    }

    public func resume() {
        isRunning = true
    }

    public func stop() {
        isRunning = false
        frameCount = 0
        lastPresentationTime = nil
        advancedOutput.reset()
        configuration.stopHandler?(session)
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
        let mediaFrame = PixelBufferFrame(
            pixelBuffer: frame.capturedImage,
            metadata: FrameMetadata(
                presentationTime: timestamp,
                sourceTime: timestamp,
                frameIndex: frameCount - 1,
                userInfo: [
                    "kakapos.camera.ar-frame": true,
                    "kakapos.camera.ar-audio": configuration.includesAudio
                ]
            )
        )
        advancedOutput.emitARFrame(.init(
            frame: mediaFrame,
            timestamp: timestamp,
            includesAudio: configuration.includesAudio
        ))
        frameHandler?(mediaFrame)
        delegate?.mediaSource(self, didOutput: mediaFrame)
    }
}
#endif
