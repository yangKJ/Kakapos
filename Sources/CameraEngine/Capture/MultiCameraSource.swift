//
//  MultiCameraSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
@available(iOS 13.0, *)
public final class MultiCameraSource {
    public struct Snapshot {
        public let isSupported: Bool
        public let frontSummaryText: String
        public let backSummaryText: String
        public let advancedEventCount: Int
        public let latestAdvancedEventSummaryText: String
    }

    public let session: AVCaptureMultiCamSession
    public let frontSource: CameraSource
    public let backSource: CameraSource
    public let advancedOutput = CameraAdvancedOutput()

    public var snapshot: Snapshot {
        Snapshot(
            isSupported: Self.isSupported,
            frontSummaryText: frontSource.summaryText,
            backSummaryText: backSource.summaryText,
            advancedEventCount: advancedOutput.eventCount,
            latestAdvancedEventSummaryText: advancedOutput.latestEventSummaryText
        )
    }

    public var summaryText: String {
        let currentSnapshot = snapshot
        return "supported \(currentSnapshot.isSupported ? "yes" : "no") · front \(currentSnapshot.frontSummaryText) · back \(currentSnapshot.backSummaryText) · events \(currentSnapshot.advancedEventCount) · latest \(currentSnapshot.latestAdvancedEventSummaryText)"
    }

    public static var isSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    public init(
        frontConfiguration: CameraCaptureConfiguration = .init(
            captureMode: .videoWithoutAudio,
            preferredPosition: .front,
            preferredDeviceTypes: [.wideAngle]
        ),
        backConfiguration: CameraCaptureConfiguration = .init(
            captureMode: .videoWithoutAudio,
            preferredPosition: .back,
            preferredDeviceTypes: [.wideAngle]
        )
    ) throws {
        self.session = AVCaptureMultiCamSession()
        self.frontSource = try CameraSource(session: session, configuration: frontConfiguration)
        self.backSource = try CameraSource(session: session, configuration: backConfiguration)
        frontSource.frameHandler = { [weak self] frame in
            self?.advancedOutput.emitMultiCamFrame(.init(position: .front, frame: frame))
        }
        backSource.frameHandler = { [weak self] frame in
            self?.advancedOutput.emitMultiCamFrame(.init(position: .back, frame: frame))
        }
    }

    public func start() {
        frontSource.start()
        backSource.start()
    }

    public func pause() {
        frontSource.pause()
        backSource.pause()
    }

    public func resume() {
        frontSource.resume()
        backSource.resume()
    }

    public func stop() {
        frontSource.stop()
        backSource.stop()
    }

    public func cancel() {
        frontSource.cancel()
        backSource.cancel()
    }
}
#endif
