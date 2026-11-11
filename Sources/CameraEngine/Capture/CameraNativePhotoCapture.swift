//
//  CameraNativePhotoCapture.swift
//  KakaposCamera
//
//  Created by Condy on 2026/10/6.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

#if canImport(UIKit) && !os(watchOS)
public enum CameraPhotoResourceFormat: String, Codable, Sendable {
    case heic, jpeg, bayerRAW, appleProRAW, uncompressedProcessed
}

public struct CameraPhotoCaptureRequest: Sendable {
    public let id: UUID
    public let format: CameraPhotoResourceFormat
    public let maximumDimensions: Bool
    public let includesLivePhoto: Bool
    public let outputDirectory: URL
    public let flashMode: AVCaptureDevice.FlashMode
    public let videoOrientation: AVCaptureVideoOrientation?
    public let suppressesShutterSound: Bool
    /// 文件发布成功后是否同时保留编码 Data；默认兼容既有消费者，失败时始终保留可恢复数据。
    public let retainsEncodedData: Bool

    public init(
        id: UUID = UUID(),
        format: CameraPhotoResourceFormat = .heic,
        maximumDimensions: Bool = false,
        includesLivePhoto: Bool = false,
        outputDirectory: URL,
        flashMode: AVCaptureDevice.FlashMode = .off,
        videoOrientation: AVCaptureVideoOrientation? = nil,
        suppressesShutterSound: Bool = false,
        retainsEncodedData: Bool = true
    ) {
        self.id = id
        self.format = format
        self.maximumDimensions = maximumDimensions
        self.includesLivePhoto = includesLivePhoto
        self.outputDirectory = outputDirectory
        self.flashMode = flashMode
        self.videoOrientation = videoOrientation
        self.suppressesShutterSound = suppressesShutterSound
        self.retainsEncodedData = retainsEncodedData
    }
}

public struct CameraPhotoCaptureCapabilities: Sendable {
    public let supportsLivePhoto: Bool
    public let supportsBayerRAW: Bool
    public let supportsAppleProRAW: Bool
    public let supportedDimensions: [CGSize]
    public let supportsHEIC: Bool
    public var supportsUncompressedProcessed: Bool = false
}

/// 单张照片的采集事实；缺失值保持未知，不以设备的晚到快照补齐。
public struct CameraPhotoCaptureFacts: Codable, Equatable, Sendable {
    public let iso: Double?
    public let exposureDurationSeconds: Double?
    public let exposureBiasEV: Double?
    public let aperture: Double?
    public let focalLengthMM: Double?
    public let lensModel: String?
    public let whiteBalanceMode: Int?
    public let requestedFlashMode: Int
    public let resolvedFlashEnabled: Bool?
    public let flashFired: Bool?
    public let flashSource: String?
    public let photoTimestampSeconds: Double?

    public init(metadata: [String: Any], requestedFlashMode: Int, resolvedFlashEnabled: Bool? = nil, photoTimestampSeconds: Double? = nil) {
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        func number(_ key: CFString) -> Double? {
            guard let value = (exif[key as String] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        let sensitivity = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        iso = sensitivity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        exposureDurationSeconds = number(kCGImagePropertyExifExposureTime).flatMap { $0 > 0 ? $0 : nil }
        exposureBiasEV = number(kCGImagePropertyExifExposureBiasValue)
        aperture = number(kCGImagePropertyExifFNumber).flatMap { $0 > 0 ? $0 : nil }
        focalLengthMM = number(kCGImagePropertyExifFocalLength).flatMap { $0 > 0 ? $0 : nil }
        lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
        whiteBalanceMode = number(kCGImagePropertyExifWhiteBalance).flatMap { (0...1).contains($0) ? Int($0) : nil }
        self.requestedFlashMode = requestedFlashMode
        self.resolvedFlashEnabled = resolvedFlashEnabled
        if let flash = number(kCGImagePropertyExifFlash), flash >= 0, flash <= 65535 {
            flashFired = Int(flash) & 1 != 0
            flashSource = "photo-exif"
        } else {
            flashFired = resolvedFlashEnabled
            flashSource = resolvedFlashEnabled == nil ? nil : "resolved-photo-settings"
        }
        self.photoTimestampSeconds = photoTimestampSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

/// 资源完全完成后才交付；原始编码数据不经过预览帧或产品滤镜。
public struct CameraPhotoCaptureArtifact: @unchecked Sendable {
    public let requestID: UUID
    public let processedData: Data?
    public let rawData: Data?
    public let processedFileURL: URL?
    public let rawFileURL: URL?
    public let livePhotoMovieURL: URL?
    public let livePhotoKeyTime: CMTime?
    public let metadata: [String: Any]
    public let dimensions: CGSize
    /// 某部分失败时仍交付已取得的资源，消费者必须保存后呈现不完整状态。
    public let captureFailure: CameraPhotoCaptureError?
    public var captureFacts: CameraPhotoCaptureFacts? = nil
}

public enum CameraPhotoCaptureError: Error, Equatable, Sendable {
    case sessionUnavailable, unsupportedFormat, livePhotoUnavailable, incompatibleCombination
    case tooManyRequests, captureFailed(String), missingResource, captureTimedOut
}

/// 每个请求持有独立 delegate；其可变结果只在锁内写入，终态只发送一次。
final class NativePhotoRequestDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let requestID: UUID
    private let outputDirectory: URL
    private let expectsRaw: Bool
    private let expectsLive: Bool
    private let retainsEncodedData: Bool
    private let requestedFlashMode: Int
    private let finish: @Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void
    private let lock = NSLock()
    private var processedData: Data?
    private var rawData: Data?
    private var processedFileURL: URL?
    private var rawFileURL: URL?
    private var movieURL: URL?
    private var keyTime: CMTime?
    private var metadata: [String: Any] = [:]
    private var captureFacts: CameraPhotoCaptureFacts?
    private var dimensions = CGSize.zero
    private var failure: CameraPhotoCaptureError?
    private var completed = false

    init(request: CameraPhotoCaptureRequest,
         finish: @escaping @Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void) {
        requestID = request.id
        outputDirectory = request.outputDirectory
        expectsRaw = request.format == .bayerRAW || request.format == .appleProRAW
        expectsLive = request.includesLivePhoto
        retainsEncodedData = request.retainsEncodedData
        requestedFlashMode = request.flashMode.rawValue
        self.finish = finish
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return }
        if let error { failure = .captureFailed(error.localizedDescription); return }
        guard let data = photo.fileDataRepresentation() else { failure = .missingResource; return }
        if photo.isRawPhoto { rawData = data } else { processedData = data }
        do {
            let suffix: String
            if photo.isRawPhoto { suffix = "-raw.dng" }
            else {
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }
                suffix = type == "public.heic" ? "-processed.heic" : (type == "public.tiff" ? "-processed.tiff" : "-processed.jpg")
            }
            let url = outputDirectory.appendingPathComponent(requestID.uuidString + suffix)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            if photo.isRawPhoto {
                rawFileURL = url
                if !retainsEncodedData { rawData = nil }
            } else {
                processedFileURL = url
                if !retainsEncodedData { processedData = nil }
            }
        } catch { failure = .captureFailed(error.localizedDescription) }
        if !photo.isRawPhoto {
            metadata = photo.metadata
            captureFacts = CameraPhotoCaptureFacts(
                metadata: photo.metadata,
                requestedFlashMode: requestedFlashMode,
                resolvedFlashEnabled: photo.resolvedSettings.isFlashEnabled,
                photoTimestampSeconds: photo.timestamp.seconds
            )
        }
        let value = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
        dimensions = CGSize(width: Int(value.width), height: Int(value.height))
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime, photoDisplayTime: CMTime,
                     resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return }
        if let error { failure = .captureFailed(error.localizedDescription) }
        else { movieURL = outputFileURL; keyTime = photoDisplayTime }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        complete(error: error.map { .captureFailed($0.localizedDescription) })
    }

    func terminate(_ error: CameraPhotoCaptureError) { complete(error: error) }

    private func complete(error: CameraPhotoCaptureError?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let missing = (processedData == nil && processedFileURL == nil)
            || (expectsRaw && rawData == nil && rawFileURL == nil)
            || (expectsLive && (movieURL == nil || keyTime == nil))
        let problem = error ?? failure ?? (missing ? .missingResource : nil)
        let result: Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>
        if processedData != nil || rawData != nil || processedFileURL != nil || rawFileURL != nil || movieURL != nil {
            result = .success(CameraPhotoCaptureArtifact(requestID: requestID,
                processedData: processedData, rawData: rawData, processedFileURL: processedFileURL, rawFileURL: rawFileURL, livePhotoMovieURL: movieURL,
                livePhotoKeyTime: keyTime, metadata: metadata, dimensions: dimensions, captureFailure: problem, captureFacts: captureFacts))
        } else { result = .failure(problem ?? .missingResource) }
        lock.unlock()
        finish(result)
    }
}
#endif
