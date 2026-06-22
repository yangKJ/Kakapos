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
    public struct BranchSnapshot {
        public let branchID: String
        public let position: CameraPosition
        public let stateDescription: String
        public let sourceSummaryText: String
        public let capabilitySummaryText: String

        public var summaryText: String {
            "\(branchID) state \(stateDescription) · \(sourceSummaryText) · capability \(capabilitySummaryText)"
        }
    }

    public struct Snapshot {
        public let isSupported: Bool
        public let unsupportedReason: String?
        public let branches: [BranchSnapshot]
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
            unsupportedReason: Self.isSupported ? nil : "AVCaptureMultiCamSession is unavailable on the current device",
            branches: [
                BranchSnapshot(
                    branchID: "front",
                    position: .front,
                    stateDescription: String(describing: frontSource.snapshot.state),
                    sourceSummaryText: frontSource.summaryText,
                    capabilitySummaryText: frontSource.capabilitySnapshot.summaryText
                ),
                BranchSnapshot(
                    branchID: "back",
                    position: .back,
                    stateDescription: String(describing: backSource.snapshot.state),
                    sourceSummaryText: backSource.summaryText,
                    capabilitySummaryText: backSource.capabilitySnapshot.summaryText
                )
            ],
            advancedEventCount: advancedOutput.eventCount,
            latestAdvancedEventSummaryText: advancedOutput.latestEventSummaryText
        )
    }

    public var summaryText: String {
        let currentSnapshot = snapshot
        let branchText = currentSnapshot.branches.map(\.summaryText).joined(separator: " · ")
        var text = "supported \(currentSnapshot.isSupported ? "yes" : "no")"
        if let unsupportedReason = currentSnapshot.unsupportedReason {
            text += " · reason \(unsupportedReason)"
        }
        text += " · \(branchText) · events \(currentSnapshot.advancedEventCount) · latest \(currentSnapshot.latestAdvancedEventSummaryText)"
        return text
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
            self?.advancedOutput.emitMultiCamFrame(.init(branchID: "front", position: .front, frame: frame, connectionDescription: "front-camera"))
        }
        backSource.frameHandler = { [weak self] frame in
            self?.advancedOutput.emitMultiCamFrame(.init(branchID: "back", position: .back, frame: frame, connectionDescription: "back-camera"))
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
