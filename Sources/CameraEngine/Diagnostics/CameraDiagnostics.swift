//
//  CameraDiagnostics.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
import CoreGraphics

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
}

public struct CameraDeviceSnapshot: Equatable, Sendable {
    public let position: CameraPosition
    public let zoomFactor: CGFloat
    public let lensPosition: Float?
    public let exposureBias: Float?
    public let torchActive: Bool
    public let flashAvailable: Bool
    public let torchAvailable: Bool
    public let focusPoint: CGPoint?
    public let exposurePoint: CGPoint?
    public let activeFormatDescription: String?
    public let activeFrameRateRange: CameraFrameRateRange?

    public init(
        position: CameraPosition,
        zoomFactor: CGFloat,
        lensPosition: Float?,
        exposureBias: Float?,
        torchActive: Bool,
        flashAvailable: Bool,
        torchAvailable: Bool,
        focusPoint: CGPoint?,
        exposurePoint: CGPoint?,
        activeFormatDescription: String?,
        activeFrameRateRange: CameraFrameRateRange?
    ) {
        self.position = position
        self.zoomFactor = zoomFactor
        self.lensPosition = lensPosition
        self.exposureBias = exposureBias
        self.torchActive = torchActive
        self.flashAvailable = flashAvailable
        self.torchAvailable = torchAvailable
        self.focusPoint = focusPoint
        self.exposurePoint = exposurePoint
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
        text += " · torch \(torchActive ? "on" : "off")"
        text += " · flash \(flashAvailable ? "ready" : "off")"
        text += " · torchAvailable \(torchAvailable ? "yes" : "no")"
        if let focusPoint {
            text += " · focus (\(String(format: "%.2f", focusPoint.x)), \(String(format: "%.2f", focusPoint.y)))"
        }
        if let exposurePoint {
            text += " · exposure (\(String(format: "%.2f", exposurePoint.x)), \(String(format: "%.2f", exposurePoint.y)))"
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
    case torchActiveChanged(Bool)
    case formatChanged(String)
    case frameRateChanged(CameraFrameRateRange)
}

public enum CameraRecordingEvent: Equatable {
    case didStart
    case didPause
    case didResume
    case didFinish
    case didCancel
    case clipCountChanged(Int)
    case durationChanged(CMTime)
}

public struct CameraMetadataObjectPayload {
    public let objects: [AVMetadataObject]
    public let timestamp: CMTime?

    public init(objects: [AVMetadataObject], timestamp: CMTime?) {
        self.objects = objects
        self.timestamp = timestamp
    }
}

public struct CameraDepthDataPayload {
    public let timestamp: CMTime

    public init(timestamp: CMTime) {
        self.timestamp = timestamp
    }
}

public struct CameraPortraitEffectsMattePayload {
    public let deliveredInPhoto: Bool

    public init(deliveredInPhoto: Bool) {
        self.deliveredInPhoto = deliveredInPhoto
    }
}

public struct CameraMultiCamFramePayload {
    public let position: CameraPosition
    public let frame: MediaFrame

    public init(position: CameraPosition, frame: MediaFrame) {
        self.position = position
        self.frame = frame
    }
}

public enum CameraAdvancedEvent {
    case metadataObjects(CameraMetadataObjectPayload)
    case depthData(CameraDepthDataPayload)
    case portraitEffectsMatte(CameraPortraitEffectsMattePayload)
    case arFrame(MediaFrame)
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
            return "metadataObjects count \(payload.objects.count) · timestamp \(timestampText)"
        case .depthData(let payload):
            return "depthData timestamp \(String(format: "%.2fs", payload.timestamp.seconds))"
        case .portraitEffectsMatte(let payload):
            return "portraitEffectsMatte delivered \(payload.deliveredInPhoto ? "photo" : "stream")"
        case .arFrame(let frame):
            return "arFrame presentation \(String(format: "%.2fs", frame.metadata.presentationTime.seconds))"
        case .multiCamFrame(let payload):
            return "multiCamFrame position \(payload.position) · presentation \(String(format: "%.2fs", payload.frame.metadata.presentationTime.seconds))"
        }
    }
}

public final class CameraAdvancedOutput {
    public var metadataObjectsHandler: ((CameraMetadataObjectPayload) -> Void)?
    public var depthDataHandler: ((CameraDepthDataPayload) -> Void)?
    public var portraitEffectsMatteHandler: ((CameraPortraitEffectsMattePayload) -> Void)?
    public var arFrameHandler: ((MediaFrame) -> Void)?
    public var multiCamFrameHandler: ((CameraMultiCamFramePayload) -> Void)?
    public var eventHandler: ((CameraAdvancedEvent) -> Void)?

    public init() {}

    public func emitMetadataObjects(_ payload: CameraMetadataObjectPayload) {
        metadataObjectsHandler?(payload)
        eventHandler?(.metadataObjects(payload))
    }

    public func emitDepthData(_ payload: CameraDepthDataPayload) {
        depthDataHandler?(payload)
        eventHandler?(.depthData(payload))
    }

    public func emitPortraitEffectsMatte(_ payload: CameraPortraitEffectsMattePayload) {
        portraitEffectsMatteHandler?(payload)
        eventHandler?(.portraitEffectsMatte(payload))
    }

    public func emitARFrame(_ frame: MediaFrame) {
        arFrameHandler?(frame)
        eventHandler?(.arFrame(frame))
    }

    public func emitMultiCamFrame(_ payload: CameraMultiCamFramePayload) {
        multiCamFrameHandler?(payload)
        eventHandler?(.multiCamFrame(payload))
    }
}
