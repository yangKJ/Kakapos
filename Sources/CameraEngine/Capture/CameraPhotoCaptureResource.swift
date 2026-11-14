//
//  CameraPhotoCaptureResource.swift
//  KakaposCamera
//
//  Created by Condy on 2026/11/11.
//

import CoreGraphics
import Foundation
import ImageIO
import KakaposMediaCore

public enum CameraPhotoCaptureOrigin: String, Codable, Sendable {
    case nativePhoto, videoFrame
}

/// 单张资源的观测值，原始日期字符串不在采集层猜测时区或转换为UTC。
public struct CameraPhotoCaptureFacts: Codable, Equatable, Sendable {
    public enum FlashSource: String, Codable, Sendable {
        case photoExif = "photo-exif"
        case resolvedSettings = "resolved-photo-settings"
    }

    public let hardwareObservation: CameraHardwareObservation?
    public let iso: Double?
    public let exposureDurationSeconds: Double?
    public let exposureBiasEV: Double?
    public let aperture: Double?
    public let focalLengthMM: Double?
    public let equivalentFocalLength35MM: Double?
    public let digitalZoomRatio: Double?
    public let deviceMake: String?
    public let deviceModel: String?
    public let lensMake: String?
    public let lensModel: String?
    public let lensSpecification: [Double]?
    public let exposureProgram: Int?
    public let exposureMode: Int?
    public let meteringMode: Int?
    public let whiteBalanceMode: Int?
    public let requestedFlashMode: Int?
    public let resolvedFlashEnabled: Bool?
    public let rawFlashValue: Int?
    public let flashFired: Bool?
    public let flashSource: FlashSource?
    public let photoTimestampSeconds: Double?
    public let dateTimeOriginal: String?
    public let offsetTimeOriginal: String?
    public let subsecTimeOriginal: String?
    public let dateTimeDigitized: String?
    public let offsetTimeDigitized: String?
    public let subsecTimeDigitized: String?

    public init(
        metadata: [String: Any],
        requestedFlashMode: Int? = nil,
        resolvedFlashEnabled: Bool? = nil,
        photoTimestampSeconds: Double? = nil,
        hardwareObservation: CameraHardwareObservation? = nil
    ) {
        self.hardwareObservation = hardwareObservation
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        func number(_ key: CFString) -> Double? {
            guard let value = (exif[key as String] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        func positive(_ key: CFString) -> Double? { number(key).flatMap { $0 > 0 ? $0 : nil } }
        func integer(_ key: CFString, maximum: Double = 65535) -> Int? {
            number(key).flatMap { $0 >= 0 && $0 <= maximum && $0.rounded(.towardZero) == $0 ? Int($0) : nil }
        }
        let sensitivity = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        iso = sensitivity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        exposureDurationSeconds = positive(kCGImagePropertyExifExposureTime)
        exposureBiasEV = number(kCGImagePropertyExifExposureBiasValue)
        aperture = positive(kCGImagePropertyExifFNumber)
        focalLengthMM = positive(kCGImagePropertyExifFocalLength)
        equivalentFocalLength35MM = positive(kCGImagePropertyExifFocalLenIn35mmFilm)
        digitalZoomRatio = positive(kCGImagePropertyExifDigitalZoomRatio)
        deviceMake = tiff[kCGImagePropertyTIFFMake as String] as? String
        deviceModel = tiff[kCGImagePropertyTIFFModel as String] as? String
        lensMake = exif[kCGImagePropertyExifLensMake as String] as? String
        lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
        let specification = (exif[kCGImagePropertyExifLensSpecification as String] as? [NSNumber])?.map(\.doubleValue)
        lensSpecification = specification.flatMap { $0.count == 4 && $0.allSatisfy { $0.isFinite && $0 >= 0 } ? $0 : nil }
        exposureProgram = integer(kCGImagePropertyExifExposureProgram)
        exposureMode = integer(kCGImagePropertyExifExposureMode)
        meteringMode = integer(kCGImagePropertyExifMeteringMode)
        whiteBalanceMode = integer(kCGImagePropertyExifWhiteBalance, maximum: 1)
        self.requestedFlashMode = requestedFlashMode
        self.resolvedFlashEnabled = resolvedFlashEnabled
        rawFlashValue = integer(kCGImagePropertyExifFlash)
        if let rawFlashValue {
            flashFired = rawFlashValue & 1 != 0
            flashSource = .photoExif
        } else {
            flashFired = resolvedFlashEnabled
            flashSource = resolvedFlashEnabled == nil ? nil : .resolvedSettings
        }
        self.photoTimestampSeconds = photoTimestampSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String
        offsetTimeOriginal = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
        subsecTimeOriginal = (exif[kCGImagePropertyExifSubsecTimeOriginal as String] as? String)
            ?? (exif[kCGImagePropertyExifSubsecTimeOriginal as String] as? NSNumber)?.stringValue
        dateTimeDigitized = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String
        offsetTimeDigitized = exif[kCGImagePropertyExifOffsetTimeDigitized as String] as? String
        subsecTimeDigitized = (exif[kCGImagePropertyExifSubsecTimeDigitized as String] as? String)
            ?? (exif[kCGImagePropertyExifSubsecTimeDigitized as String] as? NSNumber)?.stringValue
    }
}

public enum CameraPhotoCaptureError: Error, Equatable, Sendable {
    case sessionUnavailable, unsupportedFormat, livePhotoUnavailable, incompatibleCombination
    case tooManyRequests, captureFailed(String), missingResource, captureTimedOut
}

/// 每份编码资源只解析一次容器事实，公开交付后保持只读。
public struct CameraPhotoCaptureResource: @unchecked Sendable {
    public private(set) var data: Data?
    public private(set) var fileURL: URL?
    public let metadata: [String: Any]
    public let pixelDimensions: CGSize
    public let orientationRawValue: UInt32?
    public let uniformTypeIdentifier: String
    public let origin: CameraPhotoCaptureOrigin
    public let isRaw: Bool
    public let facts: CameraPhotoCaptureFacts

    public init(
        encodedData: Data,
        metadata: [String: Any],
        origin: CameraPhotoCaptureOrigin,
        isRaw: Bool = false,
        requestedFlashMode: Int? = nil,
        resolvedFlashEnabled: Bool? = nil,
        photoTimestampSeconds: Double? = nil,
        hardwareObservation: CameraHardwareObservation? = nil
    ) throws {
        guard let source = CGImageSourceCreateWithData(encodedData as CFData, nil),
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw CameraPhotoCaptureError.missingResource }
        data = encodedData
        self.metadata = metadata
        pixelDimensions = CGSize(width: width, height: height)
        uniformTypeIdentifier = type as String
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.doubleValue
        orientationRawValue = orientation.flatMap { value in
            value.isFinite && (1...8).contains(value) && value.rounded(.towardZero) == value ? UInt32(value) : nil
        }
        self.origin = origin
        self.isRaw = isRaw
        facts = CameraPhotoCaptureFacts(
            metadata: metadata,
            requestedFlashMode: requestedFlashMode,
            resolvedFlashEnabled: resolvedFlashEnabled,
            photoTimestampSeconds: photoTimestampSeconds,
            hardwareObservation: hardwareObservation
        )
    }

    /// 只由采集器在原子写入成功后发布文件，失败时原始字节仍可恢复。
    mutating func publish(at url: URL, retainingData: Bool) {
        fileURL = url
        if !retainingData { data = nil }
    }
}
