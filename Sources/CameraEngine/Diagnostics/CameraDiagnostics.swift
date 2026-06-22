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
