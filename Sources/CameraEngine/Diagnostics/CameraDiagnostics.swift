//
//  CameraDiagnostics.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
import CoreGraphics

public enum CameraCapabilityGate: String, Equatable, Sendable, Codable, CaseIterable {
    case depth
    case portraitMatte
    case metadataObjects
    case ar
    case multicam
    case torch
    case flash
}

public enum CameraFeatureSupport: String, Equatable, Sendable, Codable {
    case supported
    case unsupported
    case unknown
}

public struct CameraCapabilitySnapshot: Equatable, Sendable, Codable {
    public let supportsAudioCapture: Bool
    public let supportsPhotoCapture: Bool
    public let supportsMetadataObjects: CameraFeatureSupport
    public let supportsDepthData: CameraFeatureSupport
    public let supportsPortraitEffectsMatte: CameraFeatureSupport
    public let supportsARFrameSource: CameraFeatureSupport
    public let supportsMultiCam: CameraFeatureSupport
    public let supportsTorch: CameraFeatureSupport
    public let supportsFlash: CameraFeatureSupport
    public let currentPosition: CameraPosition
    public let isMirrored: Bool
    public let activeVideoDimensions: CGSize?

    public init(
        supportsAudioCapture: Bool,
        supportsPhotoCapture: Bool,
        supportsMetadataObjects: CameraFeatureSupport,
        supportsDepthData: CameraFeatureSupport,
        supportsPortraitEffectsMatte: CameraFeatureSupport,
        supportsARFrameSource: CameraFeatureSupport,
        supportsMultiCam: CameraFeatureSupport,
        supportsTorch: CameraFeatureSupport,
        supportsFlash: CameraFeatureSupport,
        currentPosition: CameraPosition,
        isMirrored: Bool,
        activeVideoDimensions: CGSize?
    ) {
        self.supportsAudioCapture = supportsAudioCapture
        self.supportsPhotoCapture = supportsPhotoCapture
        self.supportsMetadataObjects = supportsMetadataObjects
        self.supportsDepthData = supportsDepthData
        self.supportsPortraitEffectsMatte = supportsPortraitEffectsMatte
        self.supportsARFrameSource = supportsARFrameSource
        self.supportsMultiCam = supportsMultiCam
        self.supportsTorch = supportsTorch
        self.supportsFlash = supportsFlash
        self.currentPosition = currentPosition
        self.isMirrored = isMirrored
        self.activeVideoDimensions = activeVideoDimensions
    }

    public var summaryText: String {
        var text = "audio \(supportsAudioCapture ? "yes" : "no") · photo \(supportsPhotoCapture ? "yes" : "no")"
        text += " · metadata \(supportsMetadataObjects.rawValue)"
        text += " · depth \(supportsDepthData.rawValue)"
        text += " · portrait \(supportsPortraitEffectsMatte.rawValue)"
        text += " · ar \(supportsARFrameSource.rawValue)"
        text += " · multicam \(supportsMultiCam.rawValue)"
        text += " · torch \(supportsTorch.rawValue)"
        text += " · flash \(supportsFlash.rawValue)"
        text += " · position \(currentPosition)"
        text += " · mirrored \(isMirrored ? "yes" : "no")"
        if let activeVideoDimensions {
            text += " · size \(Int(activeVideoDimensions.width))x\(Int(activeVideoDimensions.height))"
        }
        return text
    }

    public var gateStatuses: [CameraCapabilityGate: CameraFeatureSupport] {
        [
            .metadataObjects: supportsMetadataObjects,
            .depth: supportsDepthData,
            .portraitMatte: supportsPortraitEffectsMatte,
            .ar: supportsARFrameSource,
            .multicam: supportsMultiCam,
            .torch: supportsTorch,
            .flash: supportsFlash
        ]
    }

    public func status(for gate: CameraCapabilityGate) -> CameraFeatureSupport {
        gateStatuses[gate] ?? .unknown
    }
}

public struct CameraDeviceSnapshot: Equatable, Sendable {
    public let position: CameraPosition
    public let zoomFactor: CGFloat
    public let lensPosition: Float?
    public let exposureBias: Float?
    public let iso: Float?
    public let exposureDuration: CMTime?
    public let torchActive: Bool
    public let flashAvailable: Bool
    public let torchAvailable: Bool
    public let focusPoint: CGPoint?
    public let exposurePoint: CGPoint?
    public let focusMode: CameraFocusMode?
    public let exposureMode: CameraExposureMode?
    public let whiteBalanceMode: CameraWhiteBalanceMode?
    public let activeDeviceType: String?
    public let subjectAreaMonitoringEnabled: Bool
    public let isAdjustingFocus: Bool
    public let isAdjustingExposure: Bool
    public let whiteBalanceGains: [Float]
    public let activeFormatDescription: String?
    public let activeFrameRateRange: CameraFrameRateRange?

    public init(
        position: CameraPosition,
        zoomFactor: CGFloat,
        lensPosition: Float?,
        exposureBias: Float?,
        iso: Float? = nil,
        exposureDuration: CMTime? = nil,
        torchActive: Bool,
        flashAvailable: Bool,
        torchAvailable: Bool,
        focusPoint: CGPoint?,
        exposurePoint: CGPoint?,
        focusMode: CameraFocusMode? = nil,
        exposureMode: CameraExposureMode? = nil,
        whiteBalanceMode: CameraWhiteBalanceMode? = nil,
        activeDeviceType: String? = nil,
        subjectAreaMonitoringEnabled: Bool = false,
        isAdjustingFocus: Bool = false,
        isAdjustingExposure: Bool = false,
        whiteBalanceGains: [Float] = [],
        activeFormatDescription: String?,
        activeFrameRateRange: CameraFrameRateRange?
    ) {
        self.position = position
        self.zoomFactor = zoomFactor
        self.lensPosition = lensPosition
        self.exposureBias = exposureBias
        self.iso = iso
        self.exposureDuration = exposureDuration
        self.torchActive = torchActive
        self.flashAvailable = flashAvailable
        self.torchAvailable = torchAvailable
        self.focusPoint = focusPoint
        self.exposurePoint = exposurePoint
        self.focusMode = focusMode
        self.exposureMode = exposureMode
        self.whiteBalanceMode = whiteBalanceMode
        self.activeDeviceType = activeDeviceType
        self.subjectAreaMonitoringEnabled = subjectAreaMonitoringEnabled
        self.isAdjustingFocus = isAdjustingFocus
        self.isAdjustingExposure = isAdjustingExposure
        self.whiteBalanceGains = whiteBalanceGains
        self.activeFormatDescription = activeFormatDescription
        self.activeFrameRateRange = activeFrameRateRange
    }

    public var summaryText: String {
        var text = "position \(position) · zoom \(String(format: "%.2f", zoomFactor))x"
        if let lensPosition {
            text += " · lens \(String(format: "%.2f", lensPosition))"
        }
        if let exposureBias {
            text += " · ev \(String(format: "%.2f", exposureBias))"
        }
        if let iso {
            text += " · iso \(String(format: "%.1f", iso))"
        }
        if let exposureDuration {
            text += " · shutter \(String(format: "%.4fs", exposureDuration.seconds))"
        }
        text += " · torch \(torchActive ? "on" : "off")"
        text += " · flash \(flashAvailable ? "ready" : "off")"
        text += " · torchAvailable \(torchAvailable ? "yes" : "no")"
        text += " · subjectArea \(subjectAreaMonitoringEnabled ? "on" : "off")"
        text += " · adjustingFocus \(isAdjustingFocus ? "yes" : "no")"
        text += " · adjustingExposure \(isAdjustingExposure ? "yes" : "no")"
        if let focusPoint {
            text += " · focus (\(String(format: "%.2f", focusPoint.x)), \(String(format: "%.2f", focusPoint.y)))"
        }
        if let exposurePoint {
            text += " · exposure (\(String(format: "%.2f", exposurePoint.x)), \(String(format: "%.2f", exposurePoint.y)))"
        }
        if let focusMode {
            text += " · focusMode \(focusMode)"
        }
        if let exposureMode {
            text += " · exposureMode \(exposureMode)"
        }
        if let whiteBalanceMode {
            text += " · whiteBalance \(whiteBalanceMode)"
        }
        if let activeDeviceType {
            text += " · deviceType \(activeDeviceType)"
        }
        if whiteBalanceGains.isEmpty == false {
            let gainText = whiteBalanceGains.map { String(format: "%.2f", $0) }.joined(separator: "/")
            text += " · gains \(gainText)"
        }
        if let activeFrameRateRange {
            text += " · fps \(String(format: "%.1f", activeFrameRateRange.minimumFramesPerSecond))-\(String(format: "%.1f", activeFrameRateRange.maximumFramesPerSecond))"
        }
        if let activeFormatDescription {
            text += " · format \(activeFormatDescription)"
        }
        return text
    }
}

public enum CameraDeviceEvent: Equatable {
    case positionChanged(CameraPosition)
    case zoomFactorChanged(CGFloat)
    case focusPointChanged(CGPoint)
    case exposurePointChanged(CGPoint)
    case exposureBiasChanged(Float)
    case focusModeChanged(CameraFocusMode)
    case exposureModeChanged(CameraExposureMode)
    case whiteBalanceModeChanged(CameraWhiteBalanceMode)
    case whiteBalanceGainsChanged([Float])
    case lensPositionChanged(Float)
    case exposureDurationChanged(CMTime)
    case isoChanged(Float)
    case focusAdjustmentChanged(Bool)
    case exposureAdjustmentChanged(Bool)
    case subjectAreaChanged
    case subjectAreaMonitoringChanged(Bool)
    case smoothAutoFocusChanged(Bool)
    case torchActiveChanged(Bool)
    case flashModeChanged(AVCaptureDevice.FlashMode)
    case formatChanged(String)
    case frameRateChanged(CameraFrameRateRange)
    case cleanApertureChanged(CGRect)
    case systemPressureChanged(String)
}

public enum CameraRecordingEvent {
    case willStart
    case didStart
    case didPause
    case didResume
    case didFinish
    case didCancel
    case didFail(String)
    case clipCompleted(RecordedClipSegment)
    case clipCountChanged(Int)
    case durationChanged(CMTime)
    case droppedFrame(FrameMetadata)
}

public struct CameraMetadataObjectPayload {
    public let objects: [AVMetadataObject]
    public let previewObjects: [AVMetadataObject]
    public let timestamp: CMTime?

    public init(objects: [AVMetadataObject], previewObjects: [AVMetadataObject] = [], timestamp: CMTime?) {
        self.objects = objects
        self.previewObjects = previewObjects
        self.timestamp = timestamp
    }
}

public struct CameraDepthDataPayload {
    public let timestamp: CMTime
    public let depthData: AVDepthData?
    public let isSynchronized: Bool

    public init(timestamp: CMTime, depthData: AVDepthData? = nil, isSynchronized: Bool = false) {
        self.timestamp = timestamp
        self.depthData = depthData
        self.isSynchronized = isSynchronized
    }
}

public struct CameraPortraitEffectsMattePayload {
    public let deliveredInPhoto: Bool
    public let matte: Any?
    public let timestamp: CMTime?

    public init(deliveredInPhoto: Bool, matte: Any? = nil, timestamp: CMTime? = nil) {
        self.deliveredInPhoto = deliveredInPhoto
        self.matte = matte
        self.timestamp = timestamp
    }
}

public struct CameraARFramePayload {
    public let frame: MediaFrame
    public let timestamp: CMTime
    public let includesAudio: Bool

    public init(frame: MediaFrame, timestamp: CMTime, includesAudio: Bool = false) {
        self.frame = frame
        self.timestamp = timestamp
        self.includesAudio = includesAudio
    }
}

public struct CameraMultiCamFramePayload {
    public let branchID: String
    public let position: CameraPosition
    public let frame: MediaFrame
    public let connectionDescription: String?
    public let timestamp: CMTime

    public init(position: CameraPosition, frame: MediaFrame) {
        self.branchID = String(describing: position)
        self.position = position
        self.frame = frame
        self.connectionDescription = nil
        self.timestamp = frame.metadata.presentationTime
    }

    public init(branchID: String, position: CameraPosition, frame: MediaFrame, connectionDescription: String? = nil, timestamp: CMTime? = nil) {
        self.branchID = branchID
        self.position = position
        self.frame = frame
        self.connectionDescription = connectionDescription
        self.timestamp = timestamp ?? frame.metadata.presentationTime
    }
}

public enum CameraAdvancedEvent {
    case metadataObjects(CameraMetadataObjectPayload)
    case depthData(CameraDepthDataPayload)
    case portraitEffectsMatte(CameraPortraitEffectsMattePayload)
    case arFrame(CameraARFramePayload)
    case multiCamFrame(CameraMultiCamFramePayload)

    public enum Kind: String, Equatable, Sendable, Codable {
        case metadataObjects
        case depthData
        case portraitEffectsMatte
        case arFrame
        case multiCamFrame
    }

    public var kind: Kind {
        switch self {
        case .metadataObjects:
            return .metadataObjects
        case .depthData:
            return .depthData
        case .portraitEffectsMatte:
            return .portraitEffectsMatte
        case .arFrame:
            return .arFrame
        case .multiCamFrame:
            return .multiCamFrame
        }
    }

    public var summaryText: String {
        switch self {
        case .metadataObjects(let payload):
            let timestampText = payload.timestamp.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            return "metadataObjects count \(payload.objects.count) · previewCount \(payload.previewObjects.count) · timestamp \(timestampText)"
        case .depthData(let payload):
            return "depthData synchronized \(payload.isSynchronized ? "yes" : "no") · timestamp \(String(format: "%.2fs", payload.timestamp.seconds))"
        case .portraitEffectsMatte(let payload):
            let timestampText = payload.timestamp.map { String(format: "%.2fs", $0.seconds) } ?? "n/a"
            return "portraitEffectsMatte delivered \(payload.deliveredInPhoto ? "photo" : "stream") · timestamp \(timestampText)"
        case .arFrame(let frame):
            return "arFrame presentation \(String(format: "%.2fs", frame.timestamp.seconds)) · audio \(frame.includesAudio ? "yes" : "no")"
        case .multiCamFrame(let payload):
            return "multiCamFrame branch \(payload.branchID) · position \(payload.position) · presentation \(String(format: "%.2fs", payload.timestamp.seconds))"
        }
    }
}

public final class CameraAdvancedOutput {
    public var metadataObjectsHandler: ((CameraMetadataObjectPayload) -> Void)?
    public var depthDataHandler: ((CameraDepthDataPayload) -> Void)?
    public var portraitEffectsMatteHandler: ((CameraPortraitEffectsMattePayload) -> Void)?
    public var arFrameHandler: ((CameraARFramePayload) -> Void)?
    public var multiCamFrameHandler: ((CameraMultiCamFramePayload) -> Void)?
    public var eventHandler: ((CameraAdvancedEvent) -> Void)?
    public private(set) var latestEvent: CameraAdvancedEvent?
    public private(set) var eventCount: Int = 0

    private let eventDispatcher = CameraEventDispatcher<CameraAdvancedEvent>()

    public var latestEventKind: CameraAdvancedEvent.Kind? {
        latestEvent?.kind
    }

    public var latestEventSummaryText: String {
        latestEvent?.summaryText ?? "No advanced camera events yet"
    }

    public init() {}

    @discardableResult
    public func addEventObserver(_ handler: @escaping (CameraAdvancedEvent) -> Void) -> UUID {
        eventDispatcher.addObserver(handler)
    }

    public func removeEventObserver(_ token: UUID) {
        eventDispatcher.removeObserver(token)
    }

    public func emitMetadataObjects(_ payload: CameraMetadataObjectPayload) {
        emit(.metadataObjects(payload))
    }

    public func emitDepthData(_ payload: CameraDepthDataPayload) {
        emit(.depthData(payload))
    }

    public func emitPortraitEffectsMatte(_ payload: CameraPortraitEffectsMattePayload) {
        emit(.portraitEffectsMatte(payload))
    }

    public func emitARFrame(_ frame: CameraARFramePayload) {
        emit(.arFrame(frame))
    }

    public func emitMultiCamFrame(_ payload: CameraMultiCamFramePayload) {
        emit(.multiCamFrame(payload))
    }

    public func emit(_ event: CameraAdvancedEvent) {
        record(event)
        switch event {
        case .metadataObjects(let payload):
            metadataObjectsHandler?(payload)
        case .depthData(let payload):
            depthDataHandler?(payload)
        case .portraitEffectsMatte(let payload):
            portraitEffectsMatteHandler?(payload)
        case .arFrame(let payload):
            arFrameHandler?(payload)
        case .multiCamFrame(let payload):
            multiCamFrameHandler?(payload)
        }
    }

    public func reset() {
        latestEvent = nil
        eventCount = 0
    }

    private func record(_ event: CameraAdvancedEvent) {
        latestEvent = event
        eventCount += 1
        eventHandler?(event)
        eventDispatcher.emit(event)
    }
}

public struct CameraDiagnosticsSnapshot {
    public let sessionSummaryText: String
    public let deviceSummaryText: String
    public let previewSummaryText: String?
    public let recordingSummaryText: String?
    public let capabilitySummaryText: String
    public let capabilityGateStatuses: [CameraCapabilityGate: CameraFeatureSupport]
    public let advancedEventSummaryText: String
    public let recentEvents: [String]

    public init(
        sessionSummaryText: String,
        deviceSummaryText: String,
        previewSummaryText: String?,
        recordingSummaryText: String?,
        capabilitySummaryText: String,
        capabilityGateStatuses: [CameraCapabilityGate: CameraFeatureSupport],
        advancedEventSummaryText: String,
        recentEvents: [String]
    ) {
        self.sessionSummaryText = sessionSummaryText
        self.deviceSummaryText = deviceSummaryText
        self.previewSummaryText = previewSummaryText
        self.recordingSummaryText = recordingSummaryText
        self.capabilitySummaryText = capabilitySummaryText
        self.capabilityGateStatuses = capabilityGateStatuses
        self.advancedEventSummaryText = advancedEventSummaryText
        self.recentEvents = recentEvents
    }

    public var summaryText: String {
        var text = "session \(sessionSummaryText) · device \(deviceSummaryText) · capability \(capabilitySummaryText) · advanced \(advancedEventSummaryText)"
        if let previewSummaryText {
            text += " · preview \(previewSummaryText)"
        }
        if let recordingSummaryText {
            text += " · recording \(recordingSummaryText)"
        }
        if recentEvents.isEmpty == false {
            text += " · events \(recentEvents.joined(separator: " | "))"
        }
        return text
    }
}
