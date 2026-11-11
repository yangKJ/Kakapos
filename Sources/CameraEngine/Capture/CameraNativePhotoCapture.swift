//
//  CameraNativePhotoCapture.swift
//  KakaposCamera
//
//  Created by Condy on 2026/10/6.
//

import AVFoundation
import CoreGraphics
import Foundation

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
    /// 文件发布成功后是否同时保留编码Data；失败时始终保留字节供恢复。
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
        retainsEncodedData: Bool = false
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
    public let supportsUncompressedProcessed: Bool
}

/// 每种照片资源独立持有原始元数据与拍摄事实，不混用RAW和处理后照片。
public struct CameraPhotoCaptureArtifact: @unchecked Sendable {
    public let requestID: UUID
    public let processedPhoto: CameraPhotoCaptureResource?
    public let rawPhoto: CameraPhotoCaptureResource?
    public let livePhotoMovieURL: URL?
    public let livePhotoKeyTime: CMTime?
    public let captureFailure: CameraPhotoCaptureError?
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
    private var processedPhoto: CameraPhotoCaptureResource?
    private var rawPhoto: CameraPhotoCaptureResource?
    private var movieURL: URL?
    private var keyTime: CMTime?
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
        var resource: CameraPhotoCaptureResource
        do {
            resource = try CameraPhotoCaptureResource(
                encodedData: data,
                metadata: photo.metadata,
                origin: .nativePhoto,
                isRaw: photo.isRawPhoto,
                requestedFlashMode: requestedFlashMode,
                resolvedFlashEnabled: photo.resolvedSettings.isFlashEnabled,
                photoTimestampSeconds: photo.timestamp.seconds
            )
        } catch { failure = .missingResource; return }
        do {
            let suffix: String
            if photo.isRawPhoto { suffix = "-raw.dng" }
            else {
                switch resource.uniformTypeIdentifier {
                case "public.heic", "public.heif": suffix = "-processed.heic"
                case "public.jpeg": suffix = "-processed.jpg"
                case "public.tiff": suffix = "-processed.tiff"
                default: throw CameraPhotoCaptureError.unsupportedFormat
                }
            }
            let url = outputDirectory.appendingPathComponent(requestID.uuidString + suffix)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            resource.publish(at: url, retainingData: retainsEncodedData)
        } catch let error as CameraPhotoCaptureError { failure = error }
        catch { failure = .captureFailed(error.localizedDescription) }
        if photo.isRawPhoto { rawPhoto = resource }
        else { processedPhoto = resource }
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
        let missing = processedPhoto == nil || (expectsRaw && rawPhoto == nil)
            || (expectsLive && (movieURL == nil || keyTime == nil))
        let problem = error ?? failure ?? (missing ? .missingResource : nil)
        let result: Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>
        if processedPhoto != nil || rawPhoto != nil || movieURL != nil {
            result = .success(CameraPhotoCaptureArtifact(requestID: requestID,
                processedPhoto: processedPhoto, rawPhoto: rawPhoto, livePhotoMovieURL: movieURL,
                livePhotoKeyTime: keyTime, captureFailure: problem))
        } else { result = .failure(problem ?? .missingResource) }
        lock.unlock()
        finish(result)
    }
}
#endif
