//
//  CameraSourceConfiguration.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
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
            return CGSize(
                width: sourceDimensions.width,
                height: (sourceDimensions.width * ratio).rounded()
            )
        default:
            guard let ratioValue = aspectRatioFactor else {
                return sourceDimensions
            }
            return CGSize(
                width: sourceDimensions.width,
                height: (sourceDimensions.width * ratioValue).rounded()
            )
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
        case .microphone:
            return "microphone"
        }
    }

    #if canImport(UIKit) && !os(watchOS)
    var realtimeType: KakaposRealtimeDeviceType {
        switch self {
        case .wideAngle:
            return .wideAngleCamera
        case .telephoto:
            return .telephotoCamera
        case .dual:
            return .duoCamera
        case .dualWide:
            return .dualWideCamera
        case .ultraWide:
            return .ultraWideAngleCamera
        case .triple:
            return .tripleCamera
        case .microphone:
            return .microphone
        }
    }
    #endif
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

    public init(
        sessionPreset: AVCaptureSession.Preset = .high,
        aspectRatio: CameraAspectRatio = .active,
        dimensions: CGSize? = nil,
        bitRate: Int = 2_000_000,
        codec: AVVideoCodecType = .h264,
        scalingMode: String = AVVideoScalingModeResizeAspectFill,
        transform: CGAffineTransform = .identity,
        maximumCaptureDuration: CMTime? = nil
    ) {
        self.sessionPreset = sessionPreset
        self.aspectRatio = aspectRatio
        self.dimensions = dimensions
        self.bitRate = bitRate
        self.codec = codec
        self.scalingMode = scalingMode
        self.transform = transform
        self.maximumCaptureDuration = maximumCaptureDuration
    }

    public func resolvedDimensions(from sourceDimensions: CGSize) -> CGSize {
        aspectRatio.resolvedDimensions(from: sourceDimensions)
    }

    #if canImport(UIKit) && !os(watchOS)
    func apply(to configuration: KakaposRealtimeVideoConfiguration) {
        configuration.preset = sessionPreset
        configuration.aspectRatio = aspectRatio.realtimeValue
        configuration.dimensions = dimensions
        configuration.bitRate = bitRate
        configuration.codec = codec
        configuration.scalingMode = scalingMode
        configuration.transform = transform
        configuration.maximumCaptureDuration = maximumCaptureDuration
    }
    #endif
}

public struct CameraPhotoConfiguration: Equatable, Sendable {
    public var sessionPreset: AVCaptureSession.Preset
    public var flashMode: AVCaptureDevice.FlashMode
    public var isHighResolutionEnabled: Bool
    public var generateThumbnail: Bool
    public var photoQualityMode: CameraPhotoQualityMode

    public init(
        sessionPreset: AVCaptureSession.Preset = .photo,
        flashMode: AVCaptureDevice.FlashMode = .off,
        isHighResolutionEnabled: Bool = true,
        generateThumbnail: Bool = true,
        photoQualityMode: CameraPhotoQualityMode = .balanced
    ) {
        self.sessionPreset = sessionPreset
        self.flashMode = flashMode
        self.isHighResolutionEnabled = isHighResolutionEnabled
        self.generateThumbnail = generateThumbnail
        self.photoQualityMode = photoQualityMode
    }

    #if canImport(UIKit) && !os(watchOS)
    func apply(to configuration: KakaposRealtimePhotoConfiguration) {
        configuration.preset = sessionPreset
        configuration.flashMode = flashMode
        configuration.isHighResolutionEnabled = isHighResolutionEnabled
        configuration.generateThumbnail = generateThumbnail
        configuration.photoQualityPrioritization = photoQualityMode.realtimeValue
    }
    #endif
}

public struct CameraSourceConfiguration: Equatable, Sendable {
    public var captureMode: CameraCaptureMode
    public var preferredPosition: CameraPosition
    public var preferredDeviceTypes: [CameraDeviceType]
    public var mirroringMode: CameraMirroringMode
    public var automaticallyRequestsAuthorization: Bool
    public var previewGravity: AVLayerVideoGravity
    public var video: CameraVideoConfiguration
    public var photo: CameraPhotoConfiguration

    public init(
        captureMode: CameraCaptureMode = .video,
        preferredPosition: CameraPosition = .back,
        preferredDeviceTypes: [CameraDeviceType] = [.wideAngle],
        mirroringMode: CameraMirroringMode = .automatic,
        automaticallyRequestsAuthorization: Bool = false,
        previewGravity: AVLayerVideoGravity = .resizeAspectFill,
        video: CameraVideoConfiguration = CameraVideoConfiguration(),
        photo: CameraPhotoConfiguration = CameraPhotoConfiguration()
    ) {
        self.captureMode = captureMode
        self.preferredPosition = preferredPosition
        self.preferredDeviceTypes = preferredDeviceTypes
        self.mirroringMode = mirroringMode
        self.automaticallyRequestsAuthorization = automaticallyRequestsAuthorization
        self.previewGravity = previewGravity
        self.video = video
        self.photo = photo
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
}

public struct CameraPhotoCaptureResult {
    public let data: Data?
    public let metadata: [String: Any]
    public let isFromCurrentFrame: Bool

    public init(data: Data?, metadata: [String: Any], isFromCurrentFrame: Bool) {
        self.data = data
        self.metadata = metadata
        self.isFromCurrentFrame = isFromCurrentFrame
    }
}

#if canImport(UIKit) && !os(watchOS)
private extension CameraPhotoQualityMode {
    var realtimeValue: AVCapturePhotoOutput.QualityPrioritization {
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

private extension CameraAspectRatio {
    var realtimeValue: KakaposRealtimeConfiguration.AspectRatio {
        switch self {
        case .active:
            return .active
        case .square:
            return .square
        case .standard:
            return .standard
        case .standardLandscape:
            return .standardLandscape
        case .widescreen:
            return .widescreen
        case .widescreenLandscape:
            return .widescreenLandscape
        case .twitter:
            return .twitter
        case .youtube:
            return .youtube
        case .instagram:
            return .instagram
        case .instagramLandscape:
            return .instagramLandscape
        case .instagramStories:
            return .instagramStories
        case .cinematic:
            return .cinematic
        case .custom(let width, let height):
            return .custom(w: width, h: height)
        }
    }
}
#endif
