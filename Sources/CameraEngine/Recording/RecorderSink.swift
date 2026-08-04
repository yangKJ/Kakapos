//
//  RecorderSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation
import CoreVideo

public final class RecorderSink: MediaSink, @unchecked Sendable {
    public enum RecorderError: LocalizedError {
        case writerCannotAddVideoInput
        case writerCannotAddAudioInput
        case writerCannotStart(underlying: Error?)
        case noRecordedMedia
        case outputMissing

        public var errorDescription: String? {
            switch self {
            case .writerCannotAddVideoInput: return "The asset writer cannot add the video input."
            case .writerCannotAddAudioInput: return "The asset writer cannot add the audio input."
            case .writerCannotStart(let error): return error?.localizedDescription ?? "The asset writer could not start."
            case .noRecordedMedia: return "Recording finished without any media frames."
            case .outputMissing: return "Recording finished without an output media file."
            }
        }
    }

    public struct Configuration: Sendable {
        public var dimensions: CGSize?
        public var bitRate: Int?
        public var codec: AVVideoCodecType
        public var scalingMode: String
        public var transform: CGAffineTransform
        public var includesAudio: Bool
        public var audioBitRate: Int
        public var audioSampleRate: Double
        public var audioChannelCount: Int

        public init(
            dimensions: CGSize? = nil,
            bitRate: Int? = nil,
            codec: AVVideoCodecType = .h264,
            scalingMode: String = AVVideoScalingModeResizeAspectFill,
            transform: CGAffineTransform = .identity,
            includesAudio: Bool = false,
            audioBitRate: Int = 128_000,
            audioSampleRate: Double = 44_100,
            audioChannelCount: Int = 1
        ) {
            self.dimensions = dimensions
            self.bitRate = bitRate
            self.codec = codec
            self.scalingMode = scalingMode
            self.transform = transform
            self.includesAudio = includesAudio
            self.audioBitRate = audioBitRate
            self.audioSampleRate = audioSampleRate
            self.audioChannelCount = audioChannelCount
        }
    }
    public struct Snapshot: Equatable, Sendable {
        public let state: State
        public let outputURL: URL
        public let recordedClipURL: URL?
        public let totalDuration: CMTime
        public let currentClipDuration: CMTime
        public let clipCount: Int
        public let currentClipHasStarted: Bool
        public let currentClipHasVideo: Bool
        public let currentClipHasAudio: Bool
        public let recordedVideoSegmentCount: Int
        public let recordedAudioSegmentCount: Int
        public let containsVideo: Bool
        public let containsAudio: Bool
        public let lastPresentationTime: CMTime?
        public let pausedAt: CMTime?
        public let maximumDuration: CMTime?
        public let remainingDuration: CMTime?

        public var hasRecordedClip: Bool {
            recordedClipURL != nil
        }
    }

    public struct Summary {
        public let state: State
        public let outputURL: URL
        public let clipCount: Int
        public let totalDuration: CMTime
        public let currentClipDuration: CMTime
        public let hasRecordedClip: Bool
        public let lastPresentationTime: CMTime?
        public let pausedAt: CMTime?
        public let currentClipHasStarted: Bool
        public let currentClipHasVideo: Bool
        public let currentClipHasAudio: Bool
        public let recordedVideoSegmentCount: Int
        public let recordedAudioSegmentCount: Int
        public let containsVideo: Bool
        public let containsAudio: Bool
        public let maximumDuration: CMTime?
        public let remainingDuration: CMTime?

        public var summaryText: String {
            let durationText = String(format: "%.2fs", totalDuration.seconds)
            let currentClipText = String(format: "%.2fs", currentClipDuration.seconds)
            var text = "state \(state) · clips \(clipCount) · total \(durationText) · clip \(currentClipText) · recorded \(hasRecordedClip ? "yes" : "no") · started \(currentClipHasStarted ? "yes" : "no") · video \(currentClipHasVideo ? "yes" : "no") · audio \(currentClipHasAudio ? "yes" : "no") · segments v\(recordedVideoSegmentCount)/a\(recordedAudioSegmentCount)"
            text += " · payload v\(containsVideo ? "yes" : "no")/a\(containsAudio ? "yes" : "no")"
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let pausedAt {
                text += " · pausedAt \(String(format: "%.2fs", pausedAt.seconds))"
            }
            if let maximumDuration {
                text += " · max \(String(format: "%.2fs", maximumDuration.seconds))"
            }
            if let remainingDuration {
                text += " · remaining \(String(format: "%.2fs", remainingDuration.seconds))"
            }
            return text
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case preparing
        case recording
        case paused
        case finishing
        case finished
        case cancelled
        case failed
    }

    public let outputURL: URL
    public private(set) var state: State = .idle
    public private(set) var recordedClip: RecordedClip?
    public var durationChangedHandler: ((CMTime) -> Void)?
    public var stateChangedHandler: ((State) -> Void)?
    public var droppedFrameHandler: ((FrameMetadata) -> Void)?
    public var runtimeErrorHandler: ((Error) -> Void)?
    /// 编码器跟不上实时采集时，待处理帧数必须保持有界。
    public var maximumInFlightFrameCount = 6
    public var snapshot: Snapshot {
        queue.sync {
            let recordingSnapshot = session.snapshot()
            let totalRecordedDuration = recordingSnapshot.totalDuration + recordingSnapshot.currentClipDuration
            return Snapshot(
                state: state,
                outputURL: outputURL,
                recordedClipURL: recordedClip?.outputURL,
                totalDuration: recordingSnapshot.totalDuration,
                currentClipDuration: recordingSnapshot.currentClipDuration,
                clipCount: recordingSnapshot.clipCount,
                currentClipHasStarted: recordingSnapshot.currentClipHasStarted,
                currentClipHasVideo: recordingSnapshot.currentClipHasVideo,
                currentClipHasAudio: recordingSnapshot.currentClipHasAudio,
                recordedVideoSegmentCount: recordingSnapshot.recordedVideoSegmentCount,
                recordedAudioSegmentCount: recordingSnapshot.recordedAudioSegmentCount,
                containsVideo: recordedClip?.containsVideo ?? (recordingSnapshot.recordedVideoSegmentCount > 0 || recordingSnapshot.currentClipHasVideo),
                containsAudio: recordedClip?.containsAudio ?? (recordingSnapshot.recordedAudioSegmentCount > 0 || recordingSnapshot.currentClipHasAudio),
                lastPresentationTime: lastPresentationTime,
                pausedAt: pausedAt,
                maximumDuration: maximumDuration,
                remainingDuration: maximumDuration.map { max($0 - totalRecordedDuration, .zero) }
            )
        }
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
        return Summary(
            state: currentSnapshot.state,
            outputURL: currentSnapshot.outputURL,
            clipCount: currentSnapshot.clipCount,
            totalDuration: currentSnapshot.totalDuration,
            currentClipDuration: currentSnapshot.currentClipDuration,
            hasRecordedClip: currentSnapshot.hasRecordedClip,
            lastPresentationTime: currentSnapshot.lastPresentationTime,
            pausedAt: currentSnapshot.pausedAt,
            currentClipHasStarted: currentSnapshot.currentClipHasStarted,
            currentClipHasVideo: currentSnapshot.currentClipHasVideo,
            currentClipHasAudio: currentSnapshot.currentClipHasAudio,
            recordedVideoSegmentCount: currentSnapshot.recordedVideoSegmentCount,
            recordedAudioSegmentCount: currentSnapshot.recordedAudioSegmentCount,
            containsVideo: currentSnapshot.containsVideo,
            containsAudio: currentSnapshot.containsAudio,
            maximumDuration: currentSnapshot.maximumDuration,
            remainingDuration: currentSnapshot.remainingDuration
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    private let writer: AVAssetWriter
    private let configuration: Configuration
    private let session = RecordingSession()
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var pausedAt: CMTime?
    private var applyPaddingAfterResume = false
    private var hasWrittenFirstVideoFrame = false
    private var pendingLeadingAudioBuffers: [CMSampleBuffer] = []
    private var finishCompletions: [(Result<RecordedClip, Error>) -> Void] = []
    private var terminalError: Error?
    private let queue = DispatchQueue(label: "com.condy.kakapos.recorder-sink")
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true
    private var cancellationRequested = false
    private var inFlightFrameCount = 0
    public var maximumDuration: CMTime?

    public init(outputURL: URL, fileType: AVFileType = .mp4, configuration: Configuration = .init()) throws {
        self.outputURL = outputURL
        self.configuration = configuration
        try? FileManager.default.removeItem(at: outputURL)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard reserveFrameSlot() else {
            droppedFrameHandler?(frame.metadata)
            completion(.success(()))
            return
        }
        queue.async {
            defer { self.releaseFrameSlot() }
            do {
                try self.consumeOnQueue(frame)
                completion(.success(()))
            } catch {
                self.runtimeErrorHandler?(error)
                completion(.failure(error))
            }
        }
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        finishRecording { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func finishRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        rejectFurtherFrames()
        queue.async {
            switch self.state {
            case .cancelled:
                completion(.failure(VideoX.Error.exportCancelled))
                return
            case .finished where self.recordedClip != nil:
                let recordedClip = self.recordedClip!
                completion(.success(recordedClip))
                return
            case .failed:
                completion(.failure(self.terminalError ?? RecorderError.noRecordedMedia))
                return
            case .finishing:
                self.finishCompletions.append(completion)
                return
            case .recording, .paused:
                break
            default:
                let error = RecorderError.noRecordedMedia
                self.terminalError = error
                self.setState(.failed)
                completion(.failure(error))
                return
            }
            self.finishCompletions.append(completion)
            let wasPaused = self.state == .paused
            self.setState(.finishing)
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            self.writer.finishWriting {
                self.queue.async {
                    guard self.state == .finishing else { return }
                    if self.isCancellationRequested() {
                        self.completeCancellation()
                        return
                    }
                    self.session.finalizeCurrentClipIfNeeded()
                    if wasPaused, let lastPresentationTime = self.lastPresentationTime {
                        self.session.trimLastClipEndingIfNeeded(to: lastPresentationTime)
                    }
                    if self.writer.status != .completed {
                        let error = self.writer.error ?? RecorderError.outputMissing
                        self.terminalError = error
                        self.setState(.failed)
                        self.runtimeErrorHandler?(error)
                        self.resolveFinishCompletions(with: .failure(error))
                    } else if FileManager.default.fileExists(atPath: self.outputURL.path) {
                        let clip = self.session.makeRecordedClip(
                            outputURL: self.outputURL,
                            fallbackStartedAt: self.startTime,
                            fallbackEndedAt: self.lastPresentationTime
                        )
                        self.recordedClip = clip
                        self.setState(.finished)
                        self.resolveFinishCompletions(with: .success(clip))
                    } else {
                        let error = RecorderError.outputMissing
                        self.terminalError = error
                        self.setState(.failed)
                        self.resolveFinishCompletions(with: .failure(error))
                    }
                }
            }
        }
    }

    public func cancel() {
        requestCancellation()
        rejectFurtherFrames()
        queue.async {
            self.completeCancellation()
        }
    }

    public func pauseRecording(at time: CMTime) {
        queue.sync {
            guard state == .recording else { return }
            let normalizedPauseTime = normalizedPresentationTime(for: time)
            pausedAt = normalizedPauseTime
            session.pause(at: normalizedPauseTime)
            session.configureNextClipMinimumDuration(.zero)
            session.finalizeCurrentClipIfNeeded(preferredEndTime: normalizedPauseTime)
            applyPaddingAfterResume = false
            setState(.paused)
        }
    }

    public func pauseRecording() {
        queue.sync {
            guard state == .recording else { return }
            let time = normalizedPresentationTime(for: lastPresentationTime ?? startTime ?? .zero)
            pausedAt = time
            session.pause(at: time)
            session.configureNextClipMinimumDuration(CMTime(value: 1, timescale: 600))
            session.finalizeCurrentClipIfNeeded(preferredEndTime: time)
            applyPaddingAfterResume = true
            setState(.paused)
        }
    }

    public func resumeRecording() {
        queue.sync {
            guard state == .paused else { return }
            setState(.recording)
        }
    }

    private func consumeOnQueue(_ frame: MediaFrame) throws {
        guard canAcceptFrames() else { return }
        guard state != .paused else { return }
        guard state != .cancelled && state != .finished else { return }
        if let sampleBuffer = extractSampleBuffer(frame), CMSampleBufferGetImageBuffer(sampleBuffer) == nil {
            try appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = extractPixelBuffer(frame) else { return }
        let normalizedTime = adjustedPresentationTime(
            normalizedPresentationTime(for: frame.metadata.presentationTime),
            sampleDuration: frame.metadata.duration,
            applyPadding: applyPaddingAfterResume
        )
        try setupAudioIfNeeded()
        try setupVideoIfNeeded(pixelBuffer: pixelBuffer)
        try startIfNeeded(at: normalizedTime)
        guard let adaptor = pixelBufferAdaptor else { throw RecorderError.writerCannotAddVideoInput }
        guard adaptor.append(pixelBuffer, withPresentationTime: normalizedTime) else {
            droppedFrameHandler?(frame.metadata)
            return
        }
        session.markVideoFrame(at: normalizedTime)
        if !hasWrittenFirstVideoFrame {
            hasWrittenFirstVideoFrame = true
            try flushPendingLeadingAudioIfPossible()
        }
        updateLastPresentationTime(normalizedTime)
        durationChangedHandler?(session.snapshot().totalDuration + session.snapshot().currentClipDuration)
        if let maximumDuration {
            let recordedDuration = session.snapshot().totalDuration + session.snapshot().currentClipDuration
            if recordedDuration >= maximumDuration {
                finishRecording { _ in }
            }
        }
    }

    private func setupVideoIfNeeded(pixelBuffer: CVPixelBuffer) throws {
        guard videoInput == nil else { return }
        let width = Int(configuration.dimensions?.width ?? CGFloat(CVPixelBufferGetWidth(pixelBuffer)))
        let height = Int(configuration.dimensions?.height ?? CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        var settings: [String: Any] = [
            AVVideoCodecKey: configuration.codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: configuration.scalingMode
        ]
        if let bitRate = configuration.bitRate { settings[AVVideoAverageBitRateKey] = bitRate }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writerCannotAddVideoInput
        }
        input.transform = configuration.transform
        writer.add(input)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        videoInput = input
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) throws {
        guard configuration.includesAudio else {
            throw RecorderError.writerCannotAddAudioInput
        }
        try setupAudioIfNeeded(sampleBuffer: sampleBuffer)
        guard hasWrittenFirstVideoFrame else {
            pendingLeadingAudioBuffers.append(sampleBuffer)
            if pendingLeadingAudioBuffers.count > 3 {
                pendingLeadingAudioBuffers.removeFirst(pendingLeadingAudioBuffers.count - 3)
            }
            return
        }
        try flushPendingLeadingAudioIfPossible()
        try appendAudioSampleBuffer(sampleBuffer)
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) throws {
        let normalizedTime = adjustedPresentationTime(
            normalizedPresentationTime(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
            sampleDuration: CMSampleBufferGetDuration(sampleBuffer),
            applyPadding: applyPaddingAfterResume
        )
        try startIfNeeded(at: normalizedTime)
        guard let input = audioInput else { throw RecorderError.writerCannotAddAudioInput }
        var timingCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
        var timingInfo = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid),
            count: timingCount
        )
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: timingCount, arrayToFill: &timingInfo, entriesNeededOut: &timingCount)
        timingInfo = timingInfo.map {
            CMSampleTimingInfo(
                duration: $0.duration,
                presentationTimeStamp: normalizedTime + ($0.presentationTimeStamp - CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
                decodeTimeStamp: $0.decodeTimeStamp
            )
        }
        var rebasedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &rebasedBuffer
        )
        guard input.append(rebasedBuffer ?? sampleBuffer) else {
            droppedFrameHandler?(FrameMetadata(presentationTime: normalizedTime))
            return
        }
        session.markAudioFrame(at: normalizedTime)
        updateLastPresentationTime(normalizedTime)
    }

    private func flushPendingLeadingAudioIfPossible() throws {
        guard hasWrittenFirstVideoFrame, !pendingLeadingAudioBuffers.isEmpty else { return }
        let buffers = pendingLeadingAudioBuffers
        pendingLeadingAudioBuffers.removeAll()
        for buffer in buffers {
            try appendAudioSampleBuffer(buffer)
        }
    }

    private func setupAudioIfNeeded(sampleBuffer: CMSampleBuffer? = nil) throws {
        guard configuration.includesAudio else { return }
        guard audioInput == nil else { return }
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: configuration.audioBitRate,
            AVSampleRateKey: configuration.audioSampleRate,
            AVNumberOfChannelsKey: configuration.audioChannelCount
        ]
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings,
            sourceFormatHint: sampleBuffer.flatMap(CMSampleBufferGetFormatDescription)
        )
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
            audioInput = input
        } else { throw RecorderError.writerCannotAddAudioInput }
    }

    private func startIfNeeded(at time: CMTime) throws {
        guard state == .idle || state == .paused else { return }
        if state == .idle {
            setState(.preparing)
            guard writer.startWriting() else { throw RecorderError.writerCannotStart(underlying: writer.error) }
            writer.startSession(atSourceTime: time)
            startTime = time
            lastPresentationTime = time
        }
        session.beginClipIfNeeded(at: time)
        setState(.recording)
    }

    private func normalizedPresentationTime(for time: CMTime) -> CMTime {
        if let pausedAt, time.isValid, pausedAt.isValid {
            session.resume(at: time)
            self.pausedAt = nil
        }
        return session.normalizedTime(for: time)
    }

    private func adjustedPresentationTime(
        _ time: CMTime,
        sampleDuration: CMTime?,
        applyPadding: Bool
    ) -> CMTime {
        guard time.isValid else { return time }
        let minimumStep: CMTime
        if let sampleDuration, sampleDuration.isValid, sampleDuration > .zero {
            minimumStep = sampleDuration
        } else {
            minimumStep = CMTime(value: 1, timescale: 600)
        }

        if applyPadding, let lastPresentationTime, lastPresentationTime.isValid {
            applyPaddingAfterResume = false
            return lastPresentationTime + minimumStep
        }

        guard let lastPresentationTime, time <= lastPresentationTime else { return time }
        return lastPresentationTime + minimumStep
    }

    private func updateLastPresentationTime(_ time: CMTime) {
        guard time.isValid else { return }
        if let lastPresentationTime {
            if time > lastPresentationTime {
                self.lastPresentationTime = time
            }
        } else {
            lastPresentationTime = time
        }
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        DispatchQueue.main.async {
            self.stateChangedHandler?(newState)
        }
    }

    private func resolveFinishCompletions(with result: Result<RecordedClip, Error>) {
        let completions = finishCompletions
        finishCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func completeCancellation() {
        guard state != .finished, state != .cancelled else { return }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        setState(.cancelled)
        recordedClip = nil
        resolveFinishCompletions(with: .failure(VideoX.Error.exportCancelled))
    }

    private func requestCancellation() {
        lifecycleLock.lock()
        cancellationRequested = true
        lifecycleLock.unlock()
    }

    private func isCancellationRequested() -> Bool {
        lifecycleLock.lock()
        let result = cancellationRequested
        lifecycleLock.unlock()
        return result
    }

    private func rejectFurtherFrames() {
        lifecycleLock.lock()
        acceptsFrames = false
        lifecycleLock.unlock()
    }

    private func canAcceptFrames() -> Bool {
        lifecycleLock.lock()
        let result = acceptsFrames
        lifecycleLock.unlock()
        return result
    }

    private func reserveFrameSlot() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard acceptsFrames, inFlightFrameCount < maximumInFlightFrameCount else { return false }
        inFlightFrameCount += 1
        return true
    }

    private func releaseFrameSlot() {
        lifecycleLock.lock()
        inFlightFrameCount = max(0, inFlightFrameCount - 1)
        lifecycleLock.unlock()
    }
}
