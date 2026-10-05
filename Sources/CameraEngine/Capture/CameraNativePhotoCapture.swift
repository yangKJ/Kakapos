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
    case heic, jpeg, bayerRAW, appleProRAW
}

public struct CameraPhotoCaptureRequest: Sendable {
    public let id: UUID
    public let format: CameraPhotoResourceFormat
    public let maximumDimensions: Bool
    public let includesLivePhoto: Bool
    public let outputDirectory: URL
    public let flashMode: AVCaptureDevice.FlashMode
    public let suppressesShutterSound: Bool

    public init(id: UUID = UUID(), format: CameraPhotoResourceFormat = .heic,
                maximumDimensions: Bool = false, includesLivePhoto: Bool = false,
                outputDirectory: URL, flashMode: AVCaptureDevice.FlashMode = .off, suppressesShutterSound: Bool = false) {
        self.id = id; self.format = format; self.maximumDimensions = maximumDimensions
        self.includesLivePhoto = includesLivePhoto; self.outputDirectory = outputDirectory
        self.flashMode = flashMode
        self.suppressesShutterSound = suppressesShutterSound
    }
}

public struct CameraPhotoCaptureCapabilities: Sendable {
    public let supportsLivePhoto: Bool
    public let supportsBayerRAW: Bool
    public let supportsAppleProRAW: Bool
    public let supportedDimensions: [CGSize]
    public let supportsHEIC: Bool
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
    private let finish: @Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void
    private let lock = NSLock()
    private var processedData: Data?
    private var rawData: Data?
    private var processedFileURL: URL?
    private var rawFileURL: URL?
    private var movieURL: URL?
    private var keyTime: CMTime?
    private var metadata: [String: Any] = [:]
    private var dimensions = CGSize.zero
    private var failure: CameraPhotoCaptureError?
    private var completed = false

    init(request: CameraPhotoCaptureRequest,
         finish: @escaping @Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void) {
        requestID = request.id
        outputDirectory = request.outputDirectory
        expectsRaw = request.format == .bayerRAW || request.format == .appleProRAW
        expectsLive = request.includesLivePhoto
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
                suffix = type == "public.heic" ? "-processed.heic" : "-processed.jpg"
            }
            let url = outputDirectory.appendingPathComponent(requestID.uuidString + suffix)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            if photo.isRawPhoto { rawFileURL = url } else { processedFileURL = url }
        } catch { failure = .captureFailed(error.localizedDescription) }
        metadata = photo.metadata
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
        let missing = processedData == nil || (expectsRaw && rawData == nil) || (expectsLive && (movieURL == nil || keyTime == nil))
        let problem = error ?? failure ?? (missing ? .missingResource : nil)
        let result: Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>
        if processedData != nil || rawData != nil || movieURL != nil {
            result = .success(CameraPhotoCaptureArtifact(requestID: requestID,
                processedData: processedData, rawData: rawData, processedFileURL: processedFileURL, rawFileURL: rawFileURL, livePhotoMovieURL: movieURL,
                livePhotoKeyTime: keyTime, metadata: metadata, dimensions: dimensions, captureFailure: problem))
        } else { result = .failure(problem ?? .missingResource) }
        lock.unlock()
        finish(result)
    }
}
#endif
