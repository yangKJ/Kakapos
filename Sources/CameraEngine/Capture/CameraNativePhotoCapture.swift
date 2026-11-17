//
//  CameraNativePhotoCapture.swift
//  KakaposCamera
//
//  Created by Condy on 2026/10/6.
//

import AVFoundation
import CoreGraphics
import Foundation
import KakaposMediaCore

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

extension CameraPhotoCaptureRequest {
    func resourceURL(_ resourceID: UUID, suffix: String) -> URL {
        outputDirectory.appendingPathComponent(id.uuidString + "-" + resourceID.uuidString + suffix)
    }
}

/// 每个请求持有独立 delegate；终态在锁内冻结，编码和文件写入不占用状态锁。
final class NativePhotoRequestDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let request: CameraPhotoCaptureRequest
    private let resourceID: UUID
    private let hardwareObservation: CameraHardwareObservation?
    private var finish: (@Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void)?
    private let lock = NSLock()
    private var processedPhoto: CameraPhotoCaptureResource?
    private var rawPhoto: CameraPhotoCaptureResource?
    private var movieURL: URL?
    private var deliveredMovieURL: URL?
    private var keyTime: CMTime?
    private var failure: CameraPhotoCaptureError?
    private var completed = false
    #if DEBUG
    var _beforePublishingPhotoForTesting: (() -> Void)?
    var _beforeCompletionForTesting: (() -> Void)?
    #endif

    init(
        request: CameraPhotoCaptureRequest,
        hardwareObservation: CameraHardwareObservation?,
        resourceID: UUID = UUID(),
        finish: @escaping @Sendable (Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>) -> Void
    ) {
        self.request = request
        self.resourceID = resourceID
        self.hardwareObservation = hardwareObservation
        self.finish = finish
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock()
        let accepts = !completed
        lock.unlock()
        guard accepts else { return }
        if let error { recordFailure(.captureFailed(error.localizedDescription)); return }
        guard let data = photo.fileDataRepresentation() else { recordFailure(.missingResource); return }
        receivePhoto(data: data, metadata: photo.metadata, isRaw: photo.isRawPhoto,
            resolvedFlashEnabled: photo.resolvedSettings.isFlashEnabled, timestamp: photo.timestamp.seconds)
    }

    func receivePhoto(
        data: Data,
        metadata: [String: Any],
        isRaw: Bool,
        resolvedFlashEnabled: Bool,
        timestamp: Double
    ) {
        lock.lock()
        let accepts = !completed
        lock.unlock()
        guard accepts else { return }
        var resource: CameraPhotoCaptureResource
        do {
            resource = try CameraPhotoCaptureResource(encodedData: data, metadata: metadata,
                origin: .nativePhoto, isRaw: isRaw, requestedFlashMode: request.flashMode.rawValue,
                resolvedFlashEnabled: resolvedFlashEnabled, photoTimestampSeconds: timestamp,
                hardwareObservation: hardwareObservation)
        } catch { recordFailure(.missingResource); return }
        var problem: CameraPhotoCaptureError?
        do {
            let suffix: String
            if isRaw { suffix = "-raw.dng" }
            else {
                switch resource.uniformTypeIdentifier {
                case "public.heic", "public.heif": suffix = "-processed.heic"
                case "public.jpeg": suffix = "-processed.jpg"
                case "public.tiff": suffix = "-processed.tiff"
                default: throw CameraPhotoCaptureError.unsupportedFormat
                }
            }
            let url = request.resourceURL(resourceID, suffix: suffix)
            try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            resource.publish(at: url, retainingData: request.retainsEncodedData)
        } catch let error as CameraPhotoCaptureError { problem = error }
        catch { problem = .captureFailed(error.localizedDescription) }
        #if DEBUG
        _beforePublishingPhotoForTesting?()
        #endif
        lock.lock()
        guard !completed else {
            lock.unlock()
            if let url = resource.fileURL { try? FileManager.default.removeItem(at: url) }
            return
        }
        if failure == nil { failure = problem }
        if isRaw { rawPhoto = resource } else { processedPhoto = resource }
        lock.unlock()
    }

    private func recordFailure(_ error: CameraPhotoCaptureError) {
        lock.lock()
        defer { lock.unlock() }
        if !completed, failure == nil { failure = error }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime, photoDisplayTime: CMTime,
                     resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        receiveMovie(at: outputFileURL, keyTime: photoDisplayTime, error: error)
    }

    func receiveMovie(at url: URL, keyTime: CMTime, error: Error?) {
        lock.lock()
        if completed {
            let shouldRemove = url != deliveredMovieURL
            lock.unlock()
            if shouldRemove { removeMovieIfOwned(url) }
            return
        }
        if let error { failure = .captureFailed(error.localizedDescription) }
        else { movieURL = url; self.keyTime = keyTime }
        lock.unlock()
        if error != nil { removeMovieIfOwned(url) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        finishCapture(error: error.map { .captureFailed($0.localizedDescription) })
    }

    func terminate(_ error: CameraPhotoCaptureError) { finishCapture(error: error) }

    func finishCapture(error: CameraPhotoCaptureError? = nil) {
        lock.lock()
        guard !completed else {
            let shouldRemove = deliveredMovieURL == nil
            lock.unlock()
            if shouldRemove { removeMovieIfOwned(request.resourceURL(resourceID, suffix: ".mov")) }
            return
        }
        completed = true
        let expectsRaw = request.format == .bayerRAW || request.format == .appleProRAW
        let missing = processedPhoto == nil || (expectsRaw && rawPhoto == nil)
            || (request.includesLivePhoto && (movieURL == nil || keyTime == nil))
        let problem = error ?? failure ?? (missing ? .missingResource : nil)
        let result: Result<CameraPhotoCaptureArtifact, CameraPhotoCaptureError>
        if processedPhoto != nil || rawPhoto != nil || movieURL != nil {
            result = .success(CameraPhotoCaptureArtifact(requestID: request.id, processedPhoto: processedPhoto,
                rawPhoto: rawPhoto, livePhotoMovieURL: movieURL, livePhotoKeyTime: keyTime, captureFailure: problem))
        } else { result = .failure(problem ?? .missingResource) }
        let callback = finish
        deliveredMovieURL = movieURL
        let shouldRemoveMovie = deliveredMovieURL == nil
        finish = nil
        processedPhoto = nil; rawPhoto = nil; movieURL = nil; keyTime = nil
        lock.unlock()
        if shouldRemoveMovie { removeMovieIfOwned(request.resourceURL(resourceID, suffix: ".mov")) }
        #if DEBUG
        _beforeCompletionForTesting?()
        #endif
        callback?(result)
    }

    func cancel() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let urls = [processedPhoto?.fileURL, rawPhoto?.fileURL].compactMap { $0 }
        finish = nil
        processedPhoto = nil; rawPhoto = nil; movieURL = nil; keyTime = nil
        lock.unlock()
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
        if request.includesLivePhoto { removeMovieIfOwned(request.resourceURL(resourceID, suffix: ".mov")) }
    }

    private func removeMovieIfOwned(_ url: URL) {
        if request.includesLivePhoto, url == request.resourceURL(resourceID, suffix: ".mov") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func discard(_ artifact: CameraPhotoCaptureArtifact, request: CameraPhotoCaptureRequest, resourceID: UUID) {
        let owned = Set(["-processed.jpg", "-processed.heic", "-processed.tiff", "-raw.dng", ".mov"].map {
            request.resourceURL(resourceID, suffix: $0)
        })
        [artifact.processedPhoto?.fileURL, artifact.rawPhoto?.fileURL, artifact.livePhotoMovieURL]
            .compactMap { $0 }.filter { owned.contains($0) }.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
#endif
