//
//  CameraSourceConfiguration.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import AVFoundation
import CoreGraphics

public enum CameraAspectRatio: Equatable, Sendable {
    case active
    case square
    case standard
    case standardLandscape
    case widescreen
    case widescreenLandscape
    case twitter
    case youtube
    case instagram
    case instagramLandscape
    case instagramStories
    case cinematic
    case custom(width: Int, height: Int)

    public func resolvedDimensions(from sourceDimensions: CGSize) -> CGSize {
        switch self {
        case .active:
            return sourceDimensions
        case .square:
            let side = min(sourceDimensions.width, sourceDimensions.height)
            return CGSize(width: side, height: side)
        case .custom(let width, let height):
            guard width > 0, height > 0 else {
                return sourceDimensions
            }
            let ratio = CGFloat(height) / CGFloat(width)
            return CGSize(width: sourceDimensions.width, height: (sourceDimensions.width * ratio).rounded())
        default:
            guard let ratioValue = aspectRatioFactor else {
                return sourceDimensions
            }
            return CGSize(width: sourceDimensions.width, height: (sourceDimensions.width * ratioValue).rounded())
        }
    }

    public var ratio: CGFloat? {
        aspectRatioFactor
    }

    private var aspectRatioFactor: CGFloat? {
        switch self {
        case .active:
            return nil
        case .square:
            return 1
        case .standard:
            return 4.0 / 3.0
        case .standardLandscape:
            return 3.0 / 4.0
        case .widescreen:
            return 16.0 / 9.0
        case .widescreenLandscape:
            return 9.0 / 16.0
        case .twitter, .youtube:
            return 9.0 / 16.0
        case .instagram:
            return 5.0 / 4.0
        case .instagramLandscape:
            return 4.0 / 5.0
        case .instagramStories:
            return 16.0 / 9.0
        case .cinematic:
            return 1.0 / 2.35
        case .custom(let width, let height):
            guard width > 0 else { return nil }
            return CGFloat(height) / CGFloat(width)
        }
    }
}

public enum CameraAuthorizationStatus: Int, Equatable, Sendable, CustomStringConvertible {
    case notDetermined = 0
    case denied
    case authorized

    public var description: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        }
    }
}

public enum CameraCaptureMode: Equatable, Sendable {
    case video
    case videoWithoutAudio
    case photo

    public var requestedMediaTypes: [AVMediaType] {
        switch self {
        case .video:
            return [.video, .audio]
        case .videoWithoutAudio, .photo:
            return [.video]
        }
    }

    public var includesAudio: Bool {
        requestedMediaTypes.contains(.audio)
    }
}

public enum CameraMirroringMode: Equatable, Sendable {
    case off
    case on
    case automatic

    func resolvedValue(for position: CameraPosition) -> Bool {
        switch self {
        case .off:
            return false
        case .on:
            return true
        case .automatic:
            return position == .front
        }
    }
}

public enum CameraPhotoQualityMode: Equatable, Sendable {
    case speed
    case balanced
    case quality
}

public enum CameraDeviceType: Equatable, Sendable, CustomStringConvertible {
    case wideAngle
    case telephoto
    case dual
    case dualWide
    case ultraWide
    case triple
    case trueDepth
    case microphone

    public var description: String {
        switch self {
        case .wideAngle:
            return "wideAngle"
        case .telephoto:
            return "telephoto"
        case .dual:
            return "dual"
        case .dualWide:
            return "dualWide"
        case .ultraWide:
            return "ultraWide"
        case .triple:
            return "triple"
        case .trueDepth:
            return "trueDepth"
        case .microphone:
            return "microphone"
        }
    }
}

public enum CameraFocusMode: Equatable, Sendable {
    case continuousAuto
    case auto
    case locked
}

public enum CameraExposureMode: Equatable, Sendable {
    case continuousAuto
    case auto
    case custom
    case locked
}

public enum CameraWhiteBalanceMode: Equatable, Sendable {
    case continuousAuto
    case auto
    case locked
}

public enum CameraVideoStabilizationMode: String, Equatable, Sendable, Codable {
    case off
    case standard
    case cinematic
    case cinematicExtended
    case auto
    case previewOptimized
}

public struct CameraFrameRateRange: Equatable, Sendable {
    public var minimumFramesPerSecond: Double
    public var maximumFramesPerSecond: Double

    public init(minimumFramesPerSecond: Double, maximumFramesPerSecond: Double) {
        self.minimumFramesPerSecond = minimumFramesPerSecond
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }
}

public struct CameraVideoConfiguration: Equatable, Sendable {
    public var sessionPreset: AVCaptureSession.Preset
    public var aspectRatio: CameraAspectRatio
    public var dimensions: CGSize?
    public var bitRate: Int
    public var codec: AVVideoCodecType
    public var scalingMode: String
    public var transform: CGAffineTransform
    public var maximumCaptureDuration: CMTime?
    public var preferredFrameRateRange: CameraFrameRateRange?
    public var preferredStabilizationMode: CameraVideoStabilizationMode

    public init(
        sessionPreset: AVCaptureSession.Preset = .high,
        aspectRatio: CameraAspectRatio = .active,
        dimensions: CGSize? = nil,
        bitRate: Int = 2_000_000,
        codec: AVVideoCodecType = .h264,
        scalingMode: String = AVVideoScalingModeResizeAspectFill,
        transform: CGAffineTransform = .identity,
        maximumCaptureDuration: CMTime? = nil,
        preferredFrameRateRange: CameraFrameRateRange? = nil,
        preferredStabilizationMode: CameraVideoStabilizationMode = .auto
    ) {
        self.sessionPreset = sessionPreset
        self.aspectRatio = aspectRatio
        self.dimensions = dimensions
        self.bitRate = bitRate
        self.codec = codec
        self.scalingMode = scalingMode
        self.transform = transform
        self.maximumCaptureDuration = maximumCaptureDuration
        self.preferredFrameRateRange = preferredFrameRateRange
        self.preferredStabilizationMode = preferredStabilizationMode
    }

    public func resolvedDimensions(from sourceDimensions: CGSize) -> CGSize {
        aspectRatio.resolvedDimensions(from: sourceDimensions)
    }
}

public struct CameraAudioConfiguration: Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int
    public var bitRate: Int
    public var prefersIndependentSession: Bool

    public init(
        sampleRate: Double = 44_100,
        channelCount: Int = 1,
        bitRate: Int = 128_000,
        prefersIndependentSession: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitRate = bitRate
        self.prefersIndependentSession = prefersIndependentSession
    }
}

public struct CameraPhotoConfiguration: Equatable, Sendable {
    public var sessionPreset: AVCaptureSession.Preset
    public var flashMode: AVCaptureDevice.FlashMode
    public var isHighResolutionEnabled: Bool
    public var generateThumbnail: Bool
    public var photoQualityMode: CameraPhotoQualityMode
    public var deliversDepthData: Bool
    public var deliversPortraitEffectsMatte: Bool

    public init(
        sessionPreset: AVCaptureSession.Preset = .photo,
        flashMode: AVCaptureDevice.FlashMode = .off,
        isHighResolutionEnabled: Bool = true,
        generateThumbnail: Bool = true,
        photoQualityMode: CameraPhotoQualityMode = .balanced,
        deliversDepthData: Bool = false,
        deliversPortraitEffectsMatte: Bool = false
    ) {
        self.sessionPreset = sessionPreset
        self.flashMode = flashMode
        self.isHighResolutionEnabled = isHighResolutionEnabled
        self.generateThumbnail = generateThumbnail
        self.photoQualityMode = photoQualityMode
        self.deliversDepthData = deliversDepthData
        self.deliversPortraitEffectsMatte = deliversPortraitEffectsMatte
    }
}

public struct CameraDeviceConfiguration: Equatable, Sendable {
    public var preferredPosition: CameraPosition
    public var preferredDeviceTypes: [CameraDeviceType]
    public var mirroringMode: CameraMirroringMode
    public var focusMode: CameraFocusMode
    public var exposureMode: CameraExposureMode
    public var whiteBalanceMode: CameraWhiteBalanceMode
    public var initialZoomFactor: CGFloat
    public var enablesSmoothAutoFocus: Bool
    public var subjectAreaMonitoringEnabled: Bool

    public init(
        preferredPosition: CameraPosition = .back,
        preferredDeviceTypes: [CameraDeviceType] = [.wideAngle],
        mirroringMode: CameraMirroringMode = .automatic,
        focusMode: CameraFocusMode = .continuousAuto,
        exposureMode: CameraExposureMode = .continuousAuto,
        whiteBalanceMode: CameraWhiteBalanceMode = .continuousAuto,
        initialZoomFactor: CGFloat = 1,
        enablesSmoothAutoFocus: Bool = true,
        subjectAreaMonitoringEnabled: Bool = true
    ) {
        self.preferredPosition = preferredPosition
        self.preferredDeviceTypes = preferredDeviceTypes
        self.mirroringMode = mirroringMode
        self.focusMode = focusMode
        self.exposureMode = exposureMode
        self.whiteBalanceMode = whiteBalanceMode
        self.initialZoomFactor = initialZoomFactor
        self.enablesSmoothAutoFocus = enablesSmoothAutoFocus
        self.subjectAreaMonitoringEnabled = subjectAreaMonitoringEnabled
    }
}

public struct CameraAdvancedCaptureSettings: Equatable, Sendable {
    public var metadataObjectTypes: [AVMetadataObject.ObjectType]
    public var enablesDepthData: Bool
    public var enablesPortraitEffectsMatte: Bool
    public var enablesARFrameSource: Bool
    public var enablesMultiCam: Bool
    public var requiresSynchronizedDepthData: Bool

    public init(
        metadataObjectTypes: [AVMetadataObject.ObjectType] = [],
        enablesDepthData: Bool = false,
        enablesPortraitEffectsMatte: Bool = false,
        enablesARFrameSource: Bool = false,
        enablesMultiCam: Bool = false,
        requiresSynchronizedDepthData: Bool = true
    ) {
        self.metadataObjectTypes = metadataObjectTypes
        self.enablesDepthData = enablesDepthData
        self.enablesPortraitEffectsMatte = enablesPortraitEffectsMatte
        self.enablesARFrameSource = enablesARFrameSource
        self.enablesMultiCam = enablesMultiCam
        self.requiresSynchronizedDepthData = requiresSynchronizedDepthData
    }
}

public struct CameraCapabilityDefaults: Equatable, Sendable {
    public var enablesMetadataObjectsWhenAvailable: Bool
    public var enablesDepthDataWhenAvailable: Bool
    public var enablesPortraitEffectsMatteWhenAvailable: Bool
    public var enablesARFrameSourceWhenAvailable: Bool
    public var enablesMultiCamWhenAvailable: Bool

    public init(
        enablesMetadataObjectsWhenAvailable: Bool = false,
        enablesDepthDataWhenAvailable: Bool = false,
        enablesPortraitEffectsMatteWhenAvailable: Bool = false,
        enablesARFrameSourceWhenAvailable: Bool = false,
        enablesMultiCamWhenAvailable: Bool = false
    ) {
        self.enablesMetadataObjectsWhenAvailable = enablesMetadataObjectsWhenAvailable
        self.enablesDepthDataWhenAvailable = enablesDepthDataWhenAvailable
        self.enablesPortraitEffectsMatteWhenAvailable = enablesPortraitEffectsMatteWhenAvailable
        self.enablesARFrameSourceWhenAvailable = enablesARFrameSourceWhenAvailable
        self.enablesMultiCamWhenAvailable = enablesMultiCamWhenAvailable
    }
}

public struct CameraSourceConfiguration: Equatable, Sendable {
    public var captureMode: CameraCaptureMode
    public var preferredPosition: CameraPosition
    public var preferredDeviceTypes: [CameraDeviceType]
    public var mirroringMode: CameraMirroringMode
    public var focusMode: CameraFocusMode
    public var exposureMode: CameraExposureMode
    public var whiteBalanceMode: CameraWhiteBalanceMode
    public var initialZoomFactor: CGFloat
    public var enablesSmoothAutoFocus: Bool
    public var subjectAreaMonitoringEnabled: Bool
    public var automaticallyRequestsAuthorization: Bool
    public var previewGravity: AVLayerVideoGravity
    public var video: CameraVideoConfiguration
    public var audio: CameraAudioConfiguration
    public var photo: CameraPhotoConfiguration
    public var advanced: CameraAdvancedCaptureSettings
    public var capabilityDefaults: CameraCapabilityDefaults

    public init(
        captureMode: CameraCaptureMode = .video,
        preferredPosition: CameraPosition = .back,
        preferredDeviceTypes: [CameraDeviceType] = [.wideAngle],
        mirroringMode: CameraMirroringMode = .automatic,
        focusMode: CameraFocusMode = .continuousAuto,
        exposureMode: CameraExposureMode = .continuousAuto,
        whiteBalanceMode: CameraWhiteBalanceMode = .continuousAuto,
        initialZoomFactor: CGFloat = 1,
        enablesSmoothAutoFocus: Bool = true,
        subjectAreaMonitoringEnabled: Bool = true,
        automaticallyRequestsAuthorization: Bool = false,
        previewGravity: AVLayerVideoGravity = .resizeAspectFill,
        video: CameraVideoConfiguration = CameraVideoConfiguration(),
        audio: CameraAudioConfiguration = CameraAudioConfiguration(),
        photo: CameraPhotoConfiguration = CameraPhotoConfiguration(),
        advanced: CameraAdvancedCaptureSettings = CameraAdvancedCaptureSettings(),
        capabilityDefaults: CameraCapabilityDefaults = CameraCapabilityDefaults()
    ) {
        self.captureMode = captureMode
        self.preferredPosition = preferredPosition
        self.preferredDeviceTypes = preferredDeviceTypes
        self.mirroringMode = mirroringMode
        self.focusMode = focusMode
        self.exposureMode = exposureMode
        self.whiteBalanceMode = whiteBalanceMode
        self.initialZoomFactor = initialZoomFactor
        self.enablesSmoothAutoFocus = enablesSmoothAutoFocus
        self.subjectAreaMonitoringEnabled = subjectAreaMonitoringEnabled
        self.automaticallyRequestsAuthorization = automaticallyRequestsAuthorization
        self.previewGravity = previewGravity
        self.video = video
        self.audio = audio
        self.photo = photo
        self.advanced = advanced
        self.capabilityDefaults = capabilityDefaults
    }

    public var requestedMediaTypes: [AVMediaType] {
        captureMode.requestedMediaTypes
    }

    public func requiresAuthorization(for mediaType: AVMediaType) -> Bool {
        requestedMediaTypes.contains(mediaType)
    }

    public func effectiveMirroringValue(for position: CameraPosition) -> Bool {
        mirroringMode.resolvedValue(for: position)
    }

    public var device: CameraDeviceConfiguration {
        get {
            CameraDeviceConfiguration(
                preferredPosition: preferredPosition,
                preferredDeviceTypes: preferredDeviceTypes,
                mirroringMode: mirroringMode,
                focusMode: focusMode,
                exposureMode: exposureMode,
                whiteBalanceMode: whiteBalanceMode,
                initialZoomFactor: initialZoomFactor,
                enablesSmoothAutoFocus: enablesSmoothAutoFocus,
                subjectAreaMonitoringEnabled: subjectAreaMonitoringEnabled
            )
        }
        set {
            preferredPosition = newValue.preferredPosition
            preferredDeviceTypes = newValue.preferredDeviceTypes
            mirroringMode = newValue.mirroringMode
            focusMode = newValue.focusMode
            exposureMode = newValue.exposureMode
            whiteBalanceMode = newValue.whiteBalanceMode
            initialZoomFactor = newValue.initialZoomFactor
            enablesSmoothAutoFocus = newValue.enablesSmoothAutoFocus
            subjectAreaMonitoringEnabled = newValue.subjectAreaMonitoringEnabled
        }
    }

    public static func cameraDefaults(
        captureMode: CameraCaptureMode = .video,
        preferredPosition: CameraPosition = .back
    ) -> CameraSourceConfiguration {
        CameraSourceConfiguration(
            captureMode: captureMode,
            preferredPosition: preferredPosition,
            preferredDeviceTypes: preferredPosition == .front ? [.trueDepth, .wideAngle] : [.triple, .dualWide, .wideAngle],
            mirroringMode: .automatic,
            automaticallyRequestsAuthorization: true,
            previewGravity: .resizeAspectFill
        )
    }

    public func withVideo(_ update: (CameraVideoConfiguration) -> CameraVideoConfiguration) -> CameraSourceConfiguration {
        var copy = self
        copy.video = update(video)
        return copy
    }

    public func withAudio(_ update: (CameraAudioConfiguration) -> CameraAudioConfiguration) -> CameraSourceConfiguration {
        var copy = self
        copy.audio = update(audio)
        return copy
    }

    public func withPhoto(_ update: (CameraPhotoConfiguration) -> CameraPhotoConfiguration) -> CameraSourceConfiguration {
        var copy = self
        copy.photo = update(photo)
        return copy
    }

    public func withDevice(_ update: (CameraDeviceConfiguration) -> CameraDeviceConfiguration) -> CameraSourceConfiguration {
        var copy = self
        copy.device = update(device)
        return copy
    }

    public func withAdvanced(_ update: (CameraAdvancedCaptureSettings) -> CameraAdvancedCaptureSettings) -> CameraSourceConfiguration {
        var copy = self
        copy.advanced = update(advanced)
        return copy
    }

    public func withCapabilityDefaults(_ update: (CameraCapabilityDefaults) -> CameraCapabilityDefaults) -> CameraSourceConfiguration {
        var copy = self
        copy.capabilityDefaults = update(capabilityDefaults)
        return copy
    }
}

public typealias CameraCaptureConfiguration = CameraSourceConfiguration

public struct CameraPhotoCaptureResult {
    public let data: Data?
    public let metadata: [String: Any]
    public let isFromCurrentFrame: Bool
    public let depthDataDelivered: Bool
    public let portraitEffectsMatteDelivered: Bool

    public init(
        data: Data?,
        metadata: [String: Any],
        isFromCurrentFrame: Bool,
        depthDataDelivered: Bool = false,
        portraitEffectsMatteDelivered: Bool = false
    ) {
        self.data = data
        self.metadata = metadata
        self.isFromCurrentFrame = isFromCurrentFrame
        self.depthDataDelivered = depthDataDelivered
        self.portraitEffectsMatteDelivered = portraitEffectsMatteDelivered
    }
}

#if canImport(UIKit) && !os(watchOS)
extension CameraPhotoQualityMode {
    var avFoundationValue: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
        case .speed:
            return .speed
        case .balanced:
            return .balanced
        case .quality:
            return .quality
        }
    }
}

extension CameraAspectRatio {
    var captureRatio: CGSize? {
        switch self {
        case .active:
            return nil
        case .square:
            return CGSize(width: 1, height: 1)
        case .standard:
            return CGSize(width: 3, height: 4)
        case .standardLandscape:
            return CGSize(width: 4, height: 3)
        case .widescreen:
            return CGSize(width: 9, height: 16)
        case .widescreenLandscape, .twitter, .youtube:
            return CGSize(width: 16, height: 9)
        case .instagram:
            return CGSize(width: 4, height: 5)
        case .instagramLandscape:
            return CGSize(width: 5, height: 4)
        case .instagramStories:
            return CGSize(width: 9, height: 16)
        case .cinematic:
            return CGSize(width: 100, height: 235)
        case .custom(let width, let height):
            guard width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
    }
}

extension CameraDeviceType {
    var avFoundationTypes: [AVCaptureDevice.DeviceType] {
        switch self {
        case .wideAngle:
            return [.builtInWideAngleCamera]
        case .telephoto:
            return [.builtInTelephotoCamera]
        case .dual:
            return [.builtInDualCamera]
        case .dualWide:
            return [.builtInDualWideCamera]
        case .ultraWide:
            return [.builtInUltraWideCamera]
        case .triple:
            return [.builtInTripleCamera]
        case .trueDepth:
            return [.builtInTrueDepthCamera]
        case .microphone:
            return []
        }
    }
}

extension CameraFocusMode {
    var avFoundationMode: AVCaptureDevice.FocusMode {
        switch self {
        case .continuousAuto:
            return .continuousAutoFocus
        case .auto:
            return .autoFocus
        case .locked:
            return .locked
        }
    }

    init(_ mode: AVCaptureDevice.FocusMode) {
        switch mode {
        case .continuousAutoFocus:
            self = .continuousAuto
        case .autoFocus:
            self = .auto
        default:
            self = .locked
        }
    }
}

extension CameraExposureMode {
    var avFoundationMode: AVCaptureDevice.ExposureMode {
        switch self {
        case .continuousAuto:
            return .continuousAutoExposure
        case .auto:
            return .autoExpose
        case .custom:
            return .custom
        case .locked:
            return .locked
        }
    }

    init(_ mode: AVCaptureDevice.ExposureMode) {
        switch mode {
        case .continuousAutoExposure:
            self = .continuousAuto
        case .autoExpose:
            self = .auto
        case .custom:
            self = .custom
        default:
            self = .locked
        }
    }
}

extension CameraWhiteBalanceMode {
    var avFoundationMode: AVCaptureDevice.WhiteBalanceMode {
        switch self {
        case .continuousAuto:
            return .continuousAutoWhiteBalance
        case .auto:
            return .autoWhiteBalance
        case .locked:
            return .locked
        }
    }

    init(_ mode: AVCaptureDevice.WhiteBalanceMode) {
        switch mode {
        case .continuousAutoWhiteBalance:
            self = .continuousAuto
        case .autoWhiteBalance:
            self = .auto
        default:
            self = .locked
        }
    }
}

extension CameraVideoStabilizationMode {
    var avFoundationMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off:
            return .off
        case .standard:
            return .standard
        case .cinematic:
            return .cinematic
        case .cinematicExtended:
            return .cinematicExtended
        case .auto:
            return .auto
        case .previewOptimized:
            if #available(iOS 17.0, tvOS 17.0, *) {
                return .previewOptimized
            } else {
                return .auto
            }
        }
    }
}
#endif
