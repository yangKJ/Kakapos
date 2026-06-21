//
//  ReaderWriterExportJob.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

protocol ReaderWriterExportSession {
    func export(
        progress: ((VideoAssetExportSession.ExportProgress) -> Void)?,
        status: ((VideoAssetExportSession.Status) -> Void)?,
        completion: @escaping (Error?) -> Void
    )
    func pause()
    func resume()
    func cancel()
}

public final class ReaderWriterExportJob {
    public enum Status: Equatable {
        case idle
        case exporting
        case paused
        case completed
        case cancelled
        case failed
    }

    public struct ProgressInfo {
        public var videoProgress: Double
        public var audioProgress: Double
        public var hasVideo: Bool
        public var hasAudio: Bool
        public var finishWritingProgress: Double

        public init(
            videoProgress: Double,
            audioProgress: Double,
            hasVideo: Bool,
            hasAudio: Bool,
            finishWritingProgress: Double = 0
        ) {
            self.videoProgress = min(max(videoProgress, 0), 1)
            self.audioProgress = min(max(audioProgress, 0), 1)
            self.hasVideo = hasVideo
            self.hasAudio = hasAudio
            self.finishWritingProgress = min(max(finishWritingProgress, 0), 1)
        }

        public var fractionCompleted: Double {
            let activeCount = (hasVideo ? 1.0 : 0.0) + (hasAudio ? 1.0 : 0.0)
            guard activeCount > 0 else { return 0 }
            let total = (hasVideo ? videoProgress : 0) + (hasAudio ? audioProgress : 0)
            return total / activeCount
        }

        public var overallFractionCompleted: Double {
            guard hasVideo || hasAudio else { return finishWritingProgress }
            return min((fractionCompleted * 0.95) + (finishWritingProgress * 0.05), 1)
        }
    }

    public struct Summary {
        public let status: Status
        public let videoTrackCount: Int
        public let audioTrackCount: Int
        public let processorCount: Int
        public let lastProgressInfo: ProgressInfo?
        public let lastErrorDescription: String?

        public var summaryText: String {
            let progressText: String
            let breakdownText: String?
            if let lastProgressInfo {
                progressText = "\(Int((lastProgressInfo.overallFractionCompleted * 100).rounded()))%"
                breakdownText = [
                    "video \(percentageText(lastProgressInfo.videoProgress))",
                    "audio \(percentageText(lastProgressInfo.audioProgress))",
                    "finish \(percentageText(lastProgressInfo.finishWritingProgress))"
                ].joined(separator: " · ")
            } else {
                progressText = "n/a"
                breakdownText = nil
            }
            var text = "state \(status) · tracks \(videoTrackCount)/\(audioTrackCount) · processors \(processorCount) · progress \(progressText)"
            if let breakdownText {
                text += " · \(breakdownText)"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }

        private func percentageText(_ value: Double) -> String {
            "\(Int((value * 100).rounded()))%"
        }
    }

    public var progressHandler: ((ProgressInfo) -> Void)?
    public var statusHandler: ((Status) -> Void)?
    public var lastProgressInfo: ProgressInfo? {
        stateQueue.sync { _lastProgressInfo }
    }

    public var lastErrorDescription: String? {
        stateQueue.sync { _lastErrorDescription }
    }

    public var status: Status {
        stateQueue.sync { _status }
    }

    public var summary: Summary {
        Summary(
            status: status,
            videoTrackCount: asset.tracks(withMediaType: .video).count,
            audioTrackCount: asset.tracks(withMediaType: .audio).count,
            processorCount: videoProcessors.count,
            lastProgressInfo: lastProgressInfo,
            lastErrorDescription: lastErrorDescription
        )
    }

    private let asset: AVAsset
    private let outputURL: URL
    private let fileType: AVFileType
    private let timeRange: CMTimeRange?
    private let videoComposition: AVVideoComposition?
    private let audioMix: AVAudioMix?
    private let videoProcessors: [FrameProcessor]
    private let shouldOptimizeForNetworkUse: Bool
    private let metadata: [AVMetadataItem]
    private let sessionFactory: (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.reader-writer-export.state")
    private var _status: Status = .idle
    private var _lastProgressInfo: ProgressInfo?
    private var _lastErrorDescription: String?
    private var _didDeliverCompletion = false
    private var exportSession: ReaderWriterExportSession?

    public convenience init(
        asset: AVAsset,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        videoProcessors: [FrameProcessor] = [],
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = []
    ) {
        self.init(
            asset: asset,
            outputURL: outputURL,
            fileType: fileType,
            timeRange: timeRange,
            videoComposition: videoComposition,
            audioMix: audioMix,
            videoProcessors: videoProcessors,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            sessionFactory: Self.defaultSessionFactory
        )
    }

    init(
        asset: AVAsset,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        videoProcessors: [FrameProcessor] = [],
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        sessionFactory: @escaping (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession
    ) {
        self.asset = asset
        self.outputURL = outputURL
        self.fileType = fileType
        self.timeRange = timeRange
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.videoProcessors = videoProcessors
        self.shouldOptimizeForNetworkUse = shouldOptimizeForNetworkUse
        self.metadata = metadata
        self.sessionFactory = sessionFactory
    }

    public func export(completion: @escaping (Result<URL, Error>) -> Void) {
        guard status == .idle else {
            completion(.failure(VideoX.Error.error(NSError(
                domain: "Kakapos.ReaderWriterExportJob",
                code: -2000,
                userInfo: [NSLocalizedDescriptionKey: "Export job is already running."]
            ))))
            return
        }

        do {
            let configuration = try makeConfiguration()
            let session = try sessionFactory(asset, outputURL, configuration)
            exportSession = session
            setStatus(.exporting)
            session.export(
                progress: { [weak self] progress in
                    self?.handleProgress(progress)
                },
                status: { [weak self] status in
                    self?.setStatus(Self.status(from: status))
                },
                completion: { [weak self] error in
                    guard let self else { return }
                    guard self.markCompletionDelivered() else { return }
                    self.exportSession = nil
                    if let error {
                        let mappedError = Self.mapError(error)
                        if !Self.isCancelledError(mappedError) {
                            self.storeError(mappedError)
                        }
                        if case VideoX.Error.exportCancelled = VideoX.Error.toError(mappedError) {
                            self.setStatus(.cancelled)
                        } else {
                            self.setStatus(.failed)
                        }
                        self.removePartialOutputIfNeeded()
                        completion(.failure(mappedError))
                    } else {
                        self.setStatus(.completed)
                        completion(.success(self.outputURL))
                    }
                }
            )
        } catch {
            storeError(error)
            setStatus(.failed)
            removePartialOutputIfNeeded()
            completion(.failure(Self.mapError(error)))
        }
    }

    public func pause() {
        if let exportSession {
            exportSession.pause()
            return
        }
        transitionStatusIfNeeded(from: .exporting, to: .paused)
    }

    public func resume() {
        if let exportSession {
            exportSession.resume()
            return
        }
        transitionStatusIfNeeded(from: .paused, to: .exporting)
    }

    public func cancel() {
        if status.isTerminal {
            return
        }
        if let exportSession {
            setStatus(.cancelled)
            exportSession.cancel()
            return
        }
        let shouldCancel = stateQueue.sync { () -> Bool in
            guard _status != .completed && _status != .cancelled && _status != .failed else { return false }
            _status = .cancelled
            return true
        }
        guard shouldCancel else { return }
        DispatchQueue.main.async {
            self.statusHandler?(.cancelled)
        }
    }

    func _setStatusForTesting(_ status: Status) {
        setStatus(status)
    }

    func _setProgressInfoForTesting(_ info: ProgressInfo) {
        storeProgress(info)
    }

    var _videoProcessorCountForTesting: Int {
        videoProcessors.count
    }

    private func makeConfiguration() throws -> VideoAssetExportSession.Configuration {
        let videoSettings = try makeVideoSettings()
        let audioSettings = makeAudioSettings()
        return VideoAssetExportSession.Configuration(
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            videoSettings: videoSettings,
            audioSettings: audioSettings,
            timeRange: timeRange ?? CMTimeRange(start: .zero, duration: .positiveInfinity),
            metadata: metadata,
            videoComposition: videoComposition,
            audioMix: audioMix,
            videoProcessors: videoProcessors
        )
    }

    private func makeVideoSettings() throws -> [String: Any] {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoX.Error.videoTrackEmpty
        }
        let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: abs(size.width),
            AVVideoHeightKey: abs(size.height)
        ]
    }

    private func makeAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
    }

    private func handleProgress(_ progress: VideoAssetExportSession.ExportProgress) {
        guard status == .exporting else { return }
        let info = ProgressInfo(
            videoProgress: progress.videoProgress?.fractionCompleted ?? 0,
            audioProgress: progress.audioProgress?.fractionCompleted ?? 0,
            hasVideo: progress.videoProgress != nil,
            hasAudio: progress.audioProgress != nil,
            finishWritingProgress: progress.finishWritingProgress.fractionCompleted
        )
        storeProgress(info)
        DispatchQueue.main.async {
            self.progressHandler?(info)
        }
    }

    private func removePartialOutputIfNeeded() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func storeProgress(_ info: ProgressInfo) {
        guard status == .exporting else { return }
        stateQueue.sync {
            _lastProgressInfo = info
        }
    }

    private func storeError(_ error: Error) {
        let errorDescription = Self.errorDescription(for: error)
        stateQueue.sync {
            _lastErrorDescription = errorDescription
        }
    }

    private func setStatus(_ status: Status) {
        let didChange = stateQueue.sync { () -> Bool in
            if _status.isTerminal, _status != status {
                return false
            }
            guard _status != status else { return false }
            _status = status
            return true
        }
        guard didChange else { return }
        DispatchQueue.main.async {
            self.statusHandler?(status)
        }
    }

    private func transitionStatusIfNeeded(from expectedStatus: Status, to newStatus: Status) {
        let didChange = stateQueue.sync { () -> Bool in
            if _status.isTerminal, _status != newStatus {
                return false
            }
            guard _status == expectedStatus else { return false }
            _status = newStatus
            return true
        }
        guard didChange else { return }
        DispatchQueue.main.async {
            self.statusHandler?(newStatus)
        }
    }

    private static func status(from status: VideoAssetExportSession.Status) -> Status {
        switch status {
        case .idle:
            return .idle
        case .exporting:
            return .exporting
        case .paused:
            return .paused
        case .completed:
            return .completed
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        }
    }

    private static func mapError(_ error: Error) -> Error {
        switch error {
        case VideoAssetExportSession.SessionError.noTracks:
            return VideoX.Error.videoTrackEmpty
        case VideoAssetExportSession.SessionError.cannotAddVideoInput:
            return VideoX.Error.addVideoTrack
        case VideoAssetExportSession.SessionError.cancelled:
            return VideoX.Error.exportCancelled
        default:
            return VideoX.Error.toError(error)
        }
    }

    private static func errorDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain != NSCocoaErrorDomain {
            return "\(nsError.domain)#\(nsError.code)"
        }
        return nsError.localizedDescription
    }

    private func markCompletionDelivered() -> Bool {
        stateQueue.sync {
            guard _didDeliverCompletion == false else { return false }
            _didDeliverCompletion = true
            return true
        }
    }

    private static let defaultSessionFactory: (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession = { asset, outputURL, configuration in
        try VideoAssetExportSession(asset: asset, outputURL: outputURL, configuration: configuration)
    }

    private static func isCancelledError(_ error: Error) -> Bool {
        if case VideoX.Error.exportCancelled = VideoX.Error.toError(error) {
            return true
        }
        return false
    }
}

private extension ReaderWriterExportJob.Status {
    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .idle, .exporting, .paused:
            return false
        }
    }
}
