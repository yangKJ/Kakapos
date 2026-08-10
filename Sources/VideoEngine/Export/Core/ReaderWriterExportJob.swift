//
//  ReaderWriterExportJob.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
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

public final class ReaderWriterExportJob: @unchecked Sendable {
    private struct UnsafeSendableBox<T>: @unchecked Sendable {
        let value: T
    }

    public enum Status: String, Equatable, Sendable, Codable {
        case idle
        case exporting
        case paused
        case completed
        case cancelled
        case failed
    }

    public struct ProgressInfo: Equatable, Sendable, Codable {
        public enum Phase: String, Sendable, Codable {
            case idle
            case videoEncoding
            case audioEncoding
            case finishing
            case validating
        }

        public var videoProgress: Double
        public var audioProgress: Double
        public var hasVideo: Bool
        public var hasAudio: Bool
        public var finishWritingProgress: Double
        public var phase: Phase

        public init(
            videoProgress: Double,
            audioProgress: Double,
            hasVideo: Bool,
            hasAudio: Bool,
            finishWritingProgress: Double = 0,
            phase: Phase = .idle
        ) {
            self.videoProgress = min(max(videoProgress, 0), 1)
            self.audioProgress = min(max(audioProgress, 0), 1)
            self.hasVideo = hasVideo
            self.hasAudio = hasAudio
            self.finishWritingProgress = min(max(finishWritingProgress, 0), 1)
            self.phase = phase
        }

        public var fractionCompleted: Double {
            let activeCount = (hasVideo ? 1.0 : 0.0) + (hasAudio ? 1.0 : 0.0)
            guard activeCount > 0 else { return 0 }
            let total = (hasVideo ? videoProgress : 0) + (hasAudio ? audioProgress : 0)
            return total / activeCount
        }

        public var overallFractionCompleted: Double {
            guard hasVideo || hasAudio else { return finishWritingProgress }
            return max(fractionCompleted, finishWritingProgress)
        }
    }

    public struct ManifestTimeRange: Equatable, Sendable, Codable {
        public let startSeconds: Double
        public let durationSeconds: Double?
        public let endSeconds: Double?
        public let isInfinite: Bool

        public init(timeRange: CMTimeRange) {
            self.startSeconds = timeRange.start.seconds
            if timeRange.duration.isValid,
               timeRange.duration.isNumeric,
               timeRange.duration.isPositiveInfinity == false {
                self.durationSeconds = timeRange.duration.seconds
                self.endSeconds = timeRange.end.seconds
                self.isInfinite = false
            } else {
                self.durationSeconds = nil
                self.endSeconds = nil
                self.isInfinite = true
            }
        }
    }

    public struct Manifest: Equatable, Sendable, Codable {
        public let status: Status
        public let fileTypeRawValue: String
        public let timeRange: ManifestTimeRange
        public let shouldOptimizeForNetworkUse: Bool
        public let metadataCount: Int
        public let videoTrackCount: Int
        public let audioTrackCount: Int
        public let processorCount: Int
        public let hasVideoComposition: Bool
        public let hasAudioMix: Bool
        public let lastPhase: ProgressInfo.Phase
        public let lastProgressInfo: ProgressInfo?
        public let lastErrorDescription: String?
    }

    public struct Snapshot: Equatable, Sendable {
        public let status: Status
        public let fileType: AVFileType
        public let timeRange: CMTimeRange
        public let shouldOptimizeForNetworkUse: Bool
        public let metadataCount: Int
        public let videoTrackCount: Int
        public let audioTrackCount: Int
        public let processorCount: Int
        public let hasVideoComposition: Bool
        public let hasAudioMix: Bool
        public let lastPhase: ProgressInfo.Phase
        public let lastProgressInfo: ProgressInfo?
        public let lastErrorDescription: String?

        public var progressFraction: Double? {
            lastProgressInfo.map(\.overallFractionCompleted)
        }
    }

    public struct Summary {
        public let status: Status
        public let fileType: AVFileType
        public let timeRange: CMTimeRange
        public let shouldOptimizeForNetworkUse: Bool
        public let metadataCount: Int
        public let videoTrackCount: Int
        public let audioTrackCount: Int
        public let processorCount: Int
        public let hasVideoComposition: Bool
        public let hasAudioMix: Bool
        public let lastPhase: ProgressInfo.Phase
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
            text += " · phase \(lastPhase)"
            if let breakdownText {
                text += " · \(breakdownText)"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }

        public var configurationSummaryText: String {
            [
                "file \(fileType.rawValue)",
                "range \(timeRangeText(timeRange))",
                "processors \(processorCount)",
                "metadata \(metadataCount)",
                "network \(shouldOptimizeForNetworkUse ? "yes" : "no")",
                "videoComposition \(hasVideoComposition ? "yes" : "no")",
                "audioMix \(hasAudioMix ? "yes" : "no")"
            ].joined(separator: " · ")
        }

        private func percentageText(_ value: Double) -> String {
            "\(Int((value * 100).rounded()))%"
        }

        private func timeRangeText(_ timeRange: CMTimeRange) -> String {
            guard timeRange.duration.isValid,
                  timeRange.duration.isNumeric,
                  timeRange.duration.isPositiveInfinity == false else {
                return "full"
            }
            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            return String(format: "%.2fs→%.2fs", start, end)
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

    public var progressFraction: Float? {
        lastProgressInfo.map { Float($0.overallFractionCompleted) }
    }

    public var status: Status {
        stateQueue.sync { _status }
    }

    /// 独立于状态回调的性能观测；`isFinal` 可能先于主队列上的终态通知变为 `true`。
    public var performanceSnapshot: PerformanceSnapshot {
        performanceAccumulator.snapshot
    }

    public var snapshot: Snapshot {
        let dynamicState = stateQueue.sync {
            (
                status: _status,
                lastProgressInfo: _lastProgressInfo,
                lastErrorDescription: _lastErrorDescription
            )
        }
        return Snapshot(
            status: dynamicState.status,
            fileType: fileType,
            timeRange: timeRange ?? CMTimeRange(start: .zero, duration: .positiveInfinity),
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadataCount: metadata.count,
            videoTrackCount: asset.tracks(withMediaType: .video).count,
            audioTrackCount: asset.tracks(withMediaType: .audio).count,
            processorCount: videoProcessors.count,
            hasVideoComposition: videoComposition != nil,
            hasAudioMix: audioMix != nil,
            lastPhase: dynamicState.lastProgressInfo?.phase ?? .idle,
            lastProgressInfo: dynamicState.lastProgressInfo,
            lastErrorDescription: dynamicState.lastErrorDescription
        )
    }

    public var manifest: Manifest {
        let currentSnapshot = snapshot
        return Manifest(
            status: currentSnapshot.status,
            fileTypeRawValue: currentSnapshot.fileType.rawValue,
            timeRange: ManifestTimeRange(timeRange: currentSnapshot.timeRange),
            shouldOptimizeForNetworkUse: currentSnapshot.shouldOptimizeForNetworkUse,
            metadataCount: currentSnapshot.metadataCount,
            videoTrackCount: currentSnapshot.videoTrackCount,
            audioTrackCount: currentSnapshot.audioTrackCount,
            processorCount: currentSnapshot.processorCount,
            hasVideoComposition: currentSnapshot.hasVideoComposition,
            hasAudioMix: currentSnapshot.hasAudioMix,
            lastPhase: currentSnapshot.lastPhase,
            lastProgressInfo: currentSnapshot.lastProgressInfo,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
        return Summary(
            status: currentSnapshot.status,
            fileType: currentSnapshot.fileType,
            timeRange: currentSnapshot.timeRange,
            shouldOptimizeForNetworkUse: currentSnapshot.shouldOptimizeForNetworkUse,
            metadataCount: currentSnapshot.metadataCount,
            videoTrackCount: currentSnapshot.videoTrackCount,
            audioTrackCount: currentSnapshot.audioTrackCount,
            processorCount: currentSnapshot.processorCount,
            hasVideoComposition: currentSnapshot.hasVideoComposition,
            hasAudioMix: currentSnapshot.hasAudioMix,
            lastPhase: currentSnapshot.lastPhase,
            lastProgressInfo: currentSnapshot.lastProgressInfo,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
    }

    public var configurationSummaryText: String {
        summary.configurationSummaryText
    }

    private let asset: AVAsset
    private let outputURL: URL
    private let fileType: AVFileType
    private let timeRange: CMTimeRange?
    private let videoComposition: AVVideoComposition?
    private let audioMix: AVAudioMix?
    private let videoProcessors: [FrameProcessor]
    private let videoFrameProcessingTimeout: TimeInterval?
    private let shouldOptimizeForNetworkUse: Bool
    private let metadata: [AVMetadataItem]
    private let artifactValidationExpectation: VideoArtifactValidationExpectation?
    private let preflightError: Error?
    private let performanceAccumulator: ReaderWriterExportPerformanceAccumulator
    private let sessionFactory: (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.reader-writer-export.state")
    private var _status: Status = .idle
    private var _lastProgressInfo: ProgressInfo?
    private var _lastErrorDescription: String?
    private var _didDeliverCompletion = false
    private var exportSession: ReaderWriterExportSession?
    private var exportCompletion: ((Result<URL, Error>) -> Void)?

    public convenience init(
        asset: AVAsset,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        videoProcessors: [FrameProcessor] = [],
        videoFrameProcessingTimeout: TimeInterval? = nil,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        artifactValidationExpectation: VideoArtifactValidationExpectation? = nil,
        preflightError: Error? = nil
    ) {
        self.init(
            asset: asset,
            outputURL: outputURL,
            fileType: fileType,
            timeRange: timeRange,
            videoComposition: videoComposition,
            audioMix: audioMix,
            videoProcessors: videoProcessors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            artifactValidationExpectation: artifactValidationExpectation,
            preflightError: preflightError,
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
        videoFrameProcessingTimeout: TimeInterval? = nil,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        artifactValidationExpectation: VideoArtifactValidationExpectation? = nil,
        preflightError: Error? = nil,
        sessionFactory: @escaping (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession
    ) {
        self.asset = asset
        self.outputURL = outputURL
        self.fileType = fileType
        self.timeRange = timeRange
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.videoProcessors = videoProcessors
        self.videoFrameProcessingTimeout = videoFrameProcessingTimeout.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.shouldOptimizeForNetworkUse = shouldOptimizeForNetworkUse
        self.metadata = metadata
        self.artifactValidationExpectation = artifactValidationExpectation
        self.preflightError = preflightError
        self.performanceAccumulator = ReaderWriterExportPerformanceAccumulator()
        self.sessionFactory = sessionFactory
    }

    public func export(completion: @escaping (Result<URL, Error>) -> Void) {
        let didAcquireExport = stateQueue.sync { () -> Bool in
            guard _status == .idle else { return false }
            _status = .exporting
            _didDeliverCompletion = false
            exportCompletion = completion
            return true
        }
        guard didAcquireExport else {
            completion(.failure(VideoX.Error.error(NSError(
                domain: "Kakapos.ReaderWriterExportJob",
                code: -2000,
                userInfo: [NSLocalizedDescriptionKey: "Export job is already running."]
            ))))
            return
        }
        deliverStatusCallback(.exporting)

        do {
            removePartialOutputIfNeeded()
            let configuration = try makeConfiguration()
            let session = try sessionFactory(asset, outputURL, configuration)
            let shouldStartSession = stateQueue.sync { () -> Bool in
                guard _status == .exporting, _didDeliverCompletion == false else { return false }
                exportSession = session
                return true
            }
            guard shouldStartSession else {
                session.cancel()
                return
            }
            session.export(
                progress: { [weak self] progress in
                    self?.handleProgress(progress)
                },
                status: { [weak self] status in
                    self?.setStatus(Self.status(from: status))
                },
                completion: { [weak self] error in
                    guard let self else { return }
                    self.performanceAccumulator.markFinal()
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
                        self.deliverCompletion(.failure(mappedError))
                    } else {
                        if self.status == .cancelled {
                            self.removePartialOutputIfNeeded()
                            self.deliverCompletion(.failure(VideoX.Error.exportCancelled))
                        } else {
                            self.finishSuccessfulExport()
                        }
                    }
                }
            )
        } catch {
            performanceAccumulator.markFinal()
            let mappedError = Self.mapError(error)
            if status != .cancelled {
                storeError(mappedError)
                setStatus(.failed)
            }
            removePartialOutputIfNeeded()
            deliverCompletion(status == .cancelled ? .failure(VideoX.Error.exportCancelled) : .failure(mappedError))
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
        let cancellation = stateQueue.sync { () -> (didCancel: Bool, session: ReaderWriterExportSession?, hasCompletion: Bool) in
            guard _status != .completed && _status != .cancelled && _status != .failed else {
                return (false, nil, false)
            }
            _status = .cancelled
            return (true, exportSession, exportCompletion != nil)
        }
        guard cancellation.didCancel else { return }
        performanceAccumulator.markFinal()
        deliverStatusCallback(.cancelled)
        if let session = cancellation.session {
            session.cancel()
        } else if cancellation.hasCompletion {
            removePartialOutputIfNeeded()
            deliverCompletion(.failure(VideoX.Error.exportCancelled))
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

    var _videoFrameProcessingTimeoutForTesting: TimeInterval? {
        videoFrameProcessingTimeout
    }

    private func makeConfiguration() throws -> VideoAssetExportSession.Configuration {
        if let preflightError {
            throw preflightError
        }
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
            videoProcessors: videoProcessors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout,
            videoEncodingStrategy: videoProcessors.isEmpty ? .automatic : .encoded,
            performanceAccumulator: performanceAccumulator
        )
    }

    private func makeVideoSettings() throws -> [String: Any] {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoX.Error.videoTrackEmpty
        }
        let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        return [
            AVVideoCodecKey: Self.preferredVideoCodec(for: fileType),
            AVVideoWidthKey: abs(size.width),
            AVVideoHeightKey: abs(size.height)
        ]
    }

    private static func preferredVideoCodec(for fileType: AVFileType) -> AVVideoCodecType {
        if fileType == .mov {
            return .jpeg
        }
        return .h264
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
        let info = ProgressInfo(
            videoProgress: progress.videoProgress?.fractionCompleted ?? 0,
            audioProgress: progress.audioProgress?.fractionCompleted ?? 0,
            hasVideo: progress.videoProgress != nil,
            hasAudio: progress.audioProgress != nil,
            finishWritingProgress: progress.finishWritingProgress.fractionCompleted,
            phase: progress.phase
        )
        let handler = stateQueue.sync { () -> ((ProgressInfo) -> Void)? in
            guard _status == .exporting else { return nil }
            _lastProgressInfo = info
            return progressHandler
        }
        guard let handler else { return }
        if Thread.isMainThread {
            handler(info)
        } else {
            let handlerBox = UnsafeSendableBox(value: handler)
            DispatchQueue.main.async {
                handlerBox.value(info)
            }
        }
    }

    private func removePartialOutputIfNeeded() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func finishSuccessfulExport() {
        do {
            if let expectation = artifactValidationExpectation {
                storeProgress(ProgressInfo(
                    videoProgress: 1,
                    audioProgress: 1,
                    hasVideo: true,
                    hasAudio: expectation.expectsAudio,
                    finishWritingProgress: 1,
                    phase: .validating
                ))
                _ = try VideoArtifactValidator.validate(url: outputURL, expectation: expectation)
            }
            setStatus(.completed)
            deliverCompletion(.success(outputURL))
        } catch {
            storeError(error)
            setStatus(.failed)
            removePartialOutputIfNeeded()
            deliverCompletion(.failure(error))
        }
    }

    private func storeProgress(_ info: ProgressInfo) {
        stateQueue.sync {
            guard _status == .exporting else { return }
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
        deliverStatusCallback(status)
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
        deliverStatusCallback(newStatus)
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
        case VideoAssetExportSession.SessionError.videoFrameProcessingTimedOut(let seconds):
            return VideoX.Error.frameProcessingTimedOut(seconds: seconds)
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

    private func deliverCompletion(_ result: Result<URL, Error>) {
        let completion = stateQueue.sync { () -> ((Result<URL, Error>) -> Void)? in
            guard _didDeliverCompletion == false else { return nil }
            _didDeliverCompletion = true
            let completion = exportCompletion
            exportCompletion = nil
            exportSession = nil
            return completion
        }
        completion?(result)
    }

    private func deliverStatusCallback(_ status: Status) {
        let deliverCurrentStatus = { [weak self] in
            guard let self else { return }
            let handler = self.stateQueue.sync { () -> ((Status) -> Void)? in
                guard self._status == status else { return nil }
                return self.statusHandler
            }
            handler?(status)
        }
        if Thread.isMainThread {
            deliverCurrentStatus()
        } else {
            DispatchQueue.main.async(execute: deliverCurrentStatus)
        }
    }

    nonisolated(unsafe) private static let defaultSessionFactory: (AVAsset, URL, VideoAssetExportSession.Configuration) throws -> ReaderWriterExportSession = { asset, outputURL, configuration in
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
