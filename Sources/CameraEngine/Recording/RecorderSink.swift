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
import VideoToolbox

public final class RecorderSink: MediaSink, @unchecked Sendable {
    public enum RecorderError: LocalizedError {
        case writerCannotAddVideoInput
        case writerCannotAddAudioInput
        case writerCannotStart(underlying: Error?)
        case noRecordedMedia
        case outputMissing
        case unsupportedVideoPayload

        public var errorDescription: String? {
            switch self {
            case .writerCannotAddVideoInput: return "The asset writer cannot add the video input."
            case .writerCannotAddAudioInput: return "The asset writer cannot add the audio input."
            case .writerCannotStart(let error): return error?.localizedDescription ?? "The asset writer could not start."
            case .noRecordedMedia: return "Recording finished without any media frames."
            case .outputMissing: return "Recording finished without an output media file."
            case .unsupportedVideoPayload: return "Pixel buffers must be provided for recording video frames."
            }
        }
    }

    public struct Configuration: Sendable {
        public var dimensions: CGSize?
        public var bitRate: Int?
        public var codec: AVVideoCodecType
        public var colorPolicy: VideoExportColorPolicy
        public var scalingMode: String
        public var transform: CGAffineTransform
        public var includesVideo: Bool
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
            includesVideo: Bool = true,
            includesAudio: Bool = false,
            audioBitRate: Int = 128_000,
            audioSampleRate: Double = 44_100,
            audioChannelCount: Int = 1,
            colorPolicy: VideoExportColorPolicy = .sourceCompatible
        ) {
            self.dimensions = dimensions
            self.bitRate = bitRate
            self.codec = codec
            self.colorPolicy = colorPolicy
            self.scalingMode = scalingMode
            self.transform = transform
            self.includesVideo = includesVideo
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
    public var state: State {
        lifecycleLock.lock()
        let value = _state
        lifecycleLock.unlock()
        return value
    }
    public var recordedClip: RecordedClip? {
        lifecycleLock.lock()
        let value = _recordedClip
        lifecycleLock.unlock()
        return value
    }
    public var durationChangedHandler: ((CMTime) -> Void)?
    public var stateChangedHandler: ((State) -> Void)?
    public var droppedFrameHandler: ((FrameMetadata) -> Void)?
    public var runtimeErrorHandler: ((Error) -> Void)?
    #if DEBUG
    var _willFinishWritingForTesting: (() -> Void)?
    #endif
    /// 编码器跟不上实时采集时，待处理帧数必须保持有界。
    public var maximumInFlightFrameCount = 6
    public var maximumInFlightAudioFrameCount = 12
    public var snapshot: Snapshot {
        onQueueSync {
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
    private let cadenceLock = NSLock()
    private var cadence = RecordingCadence()
    public var recordingCadence: RecordingCadence {
        cadenceLock.lock()
        defer { cadenceLock.unlock() }
        return cadence
    }
    private func updateCadence(_ update: (inout RecordingCadence) -> Void) {
        cadenceLock.lock()
        defer { cadenceLock.unlock() }
        update(&cadence)
    }

    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private struct PendingVideo {
        let buffer: CVPixelBuffer
        let time: CMTime
        let duration: CMTime
    }
    private var pendingVideo: PendingVideo?
    private var videoFormatDescription: CMVideoFormatDescription?
    private var finishingWriter = false
    private var startTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var lastVideoPresentationTime: CMTime?
    private var lastAudioPresentationTime: CMTime?
    private var pausedAt: CMTime?
    private var lastInputEnd: CMTime?
    private var resumeInputStart: CMTime?
    private var pendingFrames: [MediaFrame] = []
    private var alignmentTimer: DispatchWorkItem?
    private var isFlushing = false
    private var hasAcceptedVideoFrame = false
    private var finishCompletions: [(Result<RecordedClip, Error>) -> Void] = []
    private var terminalError: Error?
    private let queue = DispatchQueue(label: "com.condy.kakapos.recorder-sink")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let lifecycleLock = NSLock()
    private var _state: State = .idle
    private var _recordedClip: RecordedClip?
    private var acceptsFrames = true
    private var cancellationRequested = false
    private var inFlightFrameCount = 0
    private var inFlightAudioFrameCount = 0
    public var maximumDuration: CMTime?

    public init(outputURL: URL, fileType: AVFileType = .mp4, configuration: Configuration = .init()) throws {
        if configuration.includesVideo, configuration.colorPolicy.isHDR, configuration.codec != .hevc {
            throw VideoExportProfileError.incompatibleHDRCodec
        }
        self.outputURL = outputURL
        self.configuration = configuration
        try? FileManager.default.removeItem(at: outputURL)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// 离线夹具在断言暂停时序前等待编码器就绪，避免把合法实时背压当成时序错误。
    var _videoInputReadyForTesting: Bool { onQueueSync { videoInput?.isReadyForMoreMediaData ?? true } }
    var _audioInputReadyForTesting: Bool { onQueueSync { audioInput?.isReadyForMoreMediaData ?? true } }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard enqueueAcceptedFrame(frame, completion: completion) else {
            if canAcceptFrames() { updateCadence { $0.recordDrop(audio: isAudioMediaFrame(frame)) } }
            droppedFrameHandler?(frame.metadata)
            if isAudioMediaFrame(frame) && canAcceptFrames() {
                let error = MediaCoreError.audioDeliveryOverflow
                runtimeErrorHandler?(error)
                completion(.failure(error))
            } else { completion(.success(())) }
            return
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
            do { try self.flushPendingFrames(force: true) }
            catch { self.fail(error) }
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
                self.fail(error)
                completion(.failure(error))
                return
            }
            self.finishCompletions.append(completion)
            self.setState(.finishing)
            self.finishWhenVideoReady()
        }
    }

    private func finishWhenVideoReady() {
        guard state == .finishing else { return }
        guard pendingVideo != nil, let input = videoInput else { beginWriterFinish(); return }
        input.requestMediaDataWhenReady(on: queue) {
            guard self.state == .finishing, !self.finishingWriter else { return }
            do {
                guard input.isReadyForMoreMediaData else { return }
                try self.writePendingVideo(until: self.session.mediaEnd)
                self.beginWriterFinish()
            } catch { self.fail(error) }
        }
        checkFinishingEncoder()
    }
    private func checkFinishingEncoder() {
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.state == .finishing, !self.finishingWriter else { return }
            if self.writer.status == .failed { self.fail(self.writer.error ?? RecorderError.outputMissing) }
            else { self.checkFinishingEncoder() }
        }
    }
    private func beginWriterFinish() {
        guard state == .finishing, !finishingWriter else { return }
        finishingWriter = true
        if let end = session.mediaEnd, let start = startTime, end > start { writer.endSession(atSourceTime: end) }
        videoInput?.markAsFinished(); audioInput?.markAsFinished()
        #if DEBUG
        _willFinishWritingForTesting?()
        #endif
        self.writer.finishWriting {
            self.queue.async {
                guard self.state == .finishing else { return }
                if self.isCancellationRequested() {
                    self.completeCancellation()
                    return
                }
                self.session.finalizeCurrentClipIfNeeded()
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
                        fallbackEndedAt: self.session.mediaEnd,
                        recordingCadence: self.recordingCadence
                    )
                    self.storeRecordedClip(clip)
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

    public func cancel() {
        requestCancellation()
        rejectFurtherFrames()
        queue.async {
            self.completeCancellation()
        }
    }

    public func pauseRecording(at time: CMTime) {
        onQueueSync { pauseOnQueue(at: time) }
    }
    public func pauseRecording() {
        onQueueSync { pauseOnQueue(at: lastInputEnd ?? startTime ?? .zero) }
    }
    private func pauseOnQueue(at inputTime: CMTime) {
        guard state == .recording || state == .preparing || state == .idle else { return }
        if writer.status == .unknown {
            alignmentTimer?.cancel(); alignmentTimer = nil
            pendingFrames.forEach { frame in updateCadence { $0.recordDrop(audio: isAudioMediaFrame(frame)) } }
            pendingFrames.removeAll(); setState(.paused); return
        }
        do { try flushPendingFrames(force: true) } catch { fail(error); return }
        let anchor = max(inputTime, lastInputEnd ?? inputTime)
        guard anchor.isNumeric else { return }
        let mediaTime = session.normalizedTime(for: anchor)
        pausedAt = mediaTime; session.pause(at: anchor)
        session.finalizeCurrentClipIfNeeded(preferredEndTime: mediaTime)
        setState(.paused)
    }
    public func resumeRecording() {
        onQueueSync {
            guard state == .paused else { return }
            setState(writer.status == .unknown ? .preparing : .recording)
        }
    }
    func prepareToRecord() {
        onQueueSync { if state == .idle { setState(.preparing) } }
    }

    private func frameTime(_ frame: MediaFrame) -> CMTime {
        isAudioMediaFrame(frame) ? extractSampleBuffer(frame).map(CMSampleBufferGetPresentationTimeStamp) ?? frame.metadata.presentationTime : frame.metadata.presentationTime
    }
    private func flushPendingFrames(force: Bool) throws {
        guard !isFlushing, !pendingFrames.isEmpty else { return }
        let video = pendingFrames.first { !isAudioMediaFrame($0) }
        let audio = pendingFrames.first { isAudioMediaFrame($0) }
        guard video != nil || !configuration.includesVideo || (force && hasAcceptedVideoFrame && videoInput != nil) else { return }
        guard force || audio != nil || !configuration.includesAudio else { return }
        alignmentTimer?.cancel(); alignmentTimer = nil
        if let video, let buffer = extractPixelBuffer(video) { try setupVideoIfNeeded(pixelBuffer: buffer) }
        try setupAudioIfNeeded(sampleBuffer: audio.flatMap(extractSampleBuffer))
        let frames = pendingFrames.enumerated().sorted {
            let a = frameTime($0.element); let b = frameTime($1.element)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
        pendingFrames.removeAll()
        if let first = frames.first {
            let time = frameTime(first)
            if session.requiresResume { session.resume(at: time); resumeInputStart = time; pausedAt = nil }
            try startIfNeeded(at: session.normalizedTime(for: time))
        }
        isFlushing = true
        do { for frame in frames { try consumeOnQueue(frame) } }
        catch { isFlushing = false; throw error }
        isFlushing = false
        publishRecordingProgress()
    }
    private func stageIfNeeded(_ frame: MediaFrame) throws -> Bool {
        guard !isFlushing, configuration.includesVideo && configuration.includesAudio,
              !hasAcceptedVideoFrame || session.requiresResume else { return false }
        let audio = isAudioMediaFrame(frame)
        let count = pendingFrames.filter { isAudioMediaFrame($0) == audio }.count
        if count >= (audio ? maximumInFlightAudioFrameCount : maximumInFlightFrameCount) {
            if audio { throw MediaCoreError.audioDeliveryOverflow }
            updateCadence { $0.recordDrop(audio: false) }; droppedFrameHandler?(frame.metadata)
            return true
        }
        pendingFrames.append(frame)
        if alignmentTimer == nil {
            let timer = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.alignmentTimer = nil
                do { try self.flushPendingFrames(force: true) } catch { self.fail(error) }
            }
            alignmentTimer = timer; queue.asyncAfter(deadline: .now() + 0.05, execute: timer)
        }
        try flushPendingFrames(force: false)
        return true
    }

    private func consumeOnQueue(_ frame: MediaFrame) throws {
        // `consume(_:)` 已在入队前预留了帧槽；停止录制只应拒绝后续帧，
        // 不能丢弃已经被接收、但尚未在串行队列执行的帧。
        guard !isCancellationRequested() else { return }
        if state == .failed { throw terminalError ?? RecorderError.noRecordedMedia }
        guard state != .paused else { return }
        guard state != .cancelled && state != .finished else { return }
        guard frameTime(frame).isNumeric else { throw NSError(domain: "Kakapos.Recorder", code: -2101, userInfo: [NSLocalizedDescriptionKey: "录制帧时间戳必须为有限时间。"]) }
        if try stageIfNeeded(frame) { return }
        if let sampleBuffer = extractSampleBuffer(frame), CMSampleBufferGetImageBuffer(sampleBuffer) == nil {
            if let resumeInputStart, frameTime(frame) < resumeInputStart { return }
            try appendAudio(sampleBuffer)
            return
        }
        guard configuration.includesVideo else { throw RecorderError.writerCannotAddVideoInput }
        guard let pixelBuffer = extractPixelBuffer(frame) else { throw RecorderError.unsupportedVideoPayload }
        if configuration.colorPolicy.isHDR {
            let format = FrameFormat(pixelBuffer: pixelBuffer)
            guard format.dynamicRange == configuration.colorPolicy.requestedDynamicRange,
                  format.pixelFormat == .yuv420BiPlanar10BitVideoRange else {
                throw VideoExportProfileError.invalidHDROutput
            }
        }
        var duration = validDuration(frame.metadata.duration, fallback: CMTime(value: 1, timescale: 30))
        var inputTime = frame.metadata.presentationTime
        if let resumeInputStart, inputTime < resumeInputStart {
            let end = inputTime + duration
            guard end > resumeInputStart else { return }
            duration = end - resumeInputStart
            inputTime = resumeInputStart
        }
        let normalizedTime = adjustedPresentationTime(normalizedPresentationTime(for: inputTime),
            sampleDuration: duration, previousTime: lastVideoPresentationTime)
        try setupAudioIfNeeded()
        try setupVideoIfNeeded(pixelBuffer: pixelBuffer)
        try startIfNeeded(at: normalizedTime)
        guard let videoInput else { throw RecorderError.writerCannotAddVideoInput }
        guard videoInput.isReadyForMoreMediaData else {
            updateCadence { $0.recordDrop(audio: false) }; droppedFrameHandler?(frame.metadata); return
        }
        if pendingVideo != nil { try writePendingVideo(until: normalizedTime) }
        pendingVideo = PendingVideo(buffer: pixelBuffer, time: normalizedTime, duration: duration)
        updateCadence { $0.recordVideo(seconds: normalizedTime.seconds, duration: duration.seconds) }
        lastVideoPresentationTime = normalizedTime
        session.markVideoFrame(at: normalizedTime, duration: duration)
        lastInputEnd = max(lastInputEnd ?? inputTime, inputTime + duration)
        if !hasAcceptedVideoFrame {
            hasAcceptedVideoFrame = true
        }
        updateLastPresentationTime(normalizedTime)
        publishRecordingProgress()
    }
    private func publishRecordingProgress() {
        guard !isFlushing else { return }
        let progress = session.snapshot()
        let duration = progress.totalDuration + progress.currentClipDuration
        durationChangedHandler?(duration)
        if let maximumDuration, duration >= maximumDuration { finishRecording { _ in } }
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
        var compression: [String: Any] = [:]
        if let bitRate = configuration.bitRate { compression[AVVideoAverageBitRateKey] = bitRate }
        if configuration.colorPolicy.isHDR { compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel }
        if !compression.isEmpty { settings[AVVideoCompressionPropertiesKey] = compression }
        if let colors = configuration.colorPolicy.colorProperties { settings[AVVideoColorPropertiesKey] = colors }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writerCannotAddVideoInput
        }
        input.transform = configuration.transform
        writer.add(input)
        videoInput = input
    }

    private func writePendingVideo(until end: CMTime?) throws {
        guard let pending = pendingVideo, let input = videoInput else { return }
        if videoFormatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(videoFormatDescription!, imageBuffer: pending.buffer) {
            var format: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pending.buffer, formatDescriptionOut: &format) == noErr else {
                throw RecorderError.unsupportedVideoPayload
            }
            videoFormatDescription = format
        }
        let duration = end.map { max($0 - pending.time, CMTime(value: 1, timescale: 60_000)) } ?? pending.duration
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pending.time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pending.buffer,
            formatDescription: videoFormatDescription!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample, input.append(sample) else { throw writer.error ?? RecorderError.outputMissing }
        updateCadence { $0.finalizeVideoEnd(seconds: (pending.time + duration).seconds) }
        pendingVideo = nil
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) throws {
        guard configuration.includesAudio else {
            throw RecorderError.writerCannotAddAudioInput
        }
        try setupAudioIfNeeded(sampleBuffer: sampleBuffer)
        try appendAudioSampleBuffer(sampleBuffer)
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) throws {
        let inputTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = validDuration(CMSampleBufferGetDuration(sampleBuffer), fallback: .zero)
        let normalizedTime = adjustedPresentationTime(normalizedPresentationTime(for: inputTime),
            sampleDuration: duration, previousTime: lastAudioPresentationTime)
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
        guard input.isReadyForMoreMediaData else { throw MediaCoreError.audioDeliveryOverflow }
        guard input.append(rebasedBuffer ?? sampleBuffer) else {
            updateCadence { $0.recordDrop(audio: true) }
            droppedFrameHandler?(FrameMetadata(presentationTime: normalizedTime))
            return
        }
        updateCadence { $0.recordAudio(seconds: normalizedTime.seconds, duration: CMSampleBufferGetDuration(sampleBuffer).seconds) }
        lastAudioPresentationTime = normalizedTime
        session.markAudioFrame(at: normalizedTime, duration: duration)
        lastInputEnd = max(lastInputEnd ?? inputTime, inputTime + duration)
        updateLastPresentationTime(normalizedTime)
        publishRecordingProgress()
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
        guard state == .idle || state == .preparing || state == .paused else { return }
        if writer.status == .unknown {
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
        if session.requiresResume {
            session.resume(at: time); resumeInputStart = time; pausedAt = nil
        }
        return session.normalizedTime(for: time)
    }
    private func validDuration(_ duration: CMTime?, fallback: CMTime) -> CMTime {
        guard let duration, duration.isNumeric, duration > .zero else { return fallback }
        return duration
    }
    private func adjustedPresentationTime(_ time: CMTime, sampleDuration: CMTime, previousTime: CMTime?) -> CMTime {
        guard let previousTime, time <= previousTime else { return time }
        return previousTime + max(sampleDuration, CMTime(value: 1, timescale: 600))
    }
    private func onQueueSync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return body() }
        return queue.sync(execute: body)
    }
    var failureError: Error? { onQueueSync { terminalError } }
    private func fail(_ error: Error) {
        terminalError = error; rejectFurtherFrames()
        alignmentTimer?.cancel(); alignmentTimer = nil; pendingFrames.removeAll(); pendingVideo = nil
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: outputURL)
        setState(.failed); runtimeErrorHandler?(error)
        resolveFinishCompletions(with: .failure(error))
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
        lifecycleLock.lock()
        guard _state != newState else {
            lifecycleLock.unlock()
            return
        }
        _state = newState
        lifecycleLock.unlock()
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
        guard state != .finished, state != .cancelled, state != .failed else { return }
        alignmentTimer?.cancel(); alignmentTimer = nil; pendingFrames.removeAll(); pendingVideo = nil
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        setState(.cancelled)
        storeRecordedClip(nil)
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

    private func enqueueAcceptedFrame(
        _ frame: MediaFrame,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> Bool {
        lifecycleLock.lock()
        let audio = isAudioMediaFrame(frame)
        let count = audio ? inFlightAudioFrameCount : inFlightFrameCount
        let capacity = audio ? maximumInFlightAudioFrameCount : maximumInFlightFrameCount
        guard acceptsFrames, count < capacity else {
            lifecycleLock.unlock()
            return false
        }
        if audio { inFlightAudioFrameCount += 1 } else { inFlightFrameCount += 1 }
        // 入队动作与 acceptsFrames 的切换共用同一把锁，从而形成严格次序：
        // 已接受的帧一定排在 finish 请求之前，之后到达的帧一定被拒绝。
        queue.async {
            defer { self.releaseFrameSlot(audio: audio) }
            do {
                try self.consumeOnQueue(frame)
                completion(.success(()))
            } catch {
                self.fail(error)
                completion(.failure(error))
            }
        }
        lifecycleLock.unlock()
        return true
    }

    private func releaseFrameSlot(audio: Bool) {
        lifecycleLock.lock()
        if audio { inFlightAudioFrameCount = max(0, inFlightAudioFrameCount - 1) }
        else { inFlightFrameCount = max(0, inFlightFrameCount - 1) }
        lifecycleLock.unlock()
    }

    private func storeRecordedClip(_ clip: RecordedClip?) {
        lifecycleLock.lock()
        _recordedClip = clip
        lifecycleLock.unlock()
    }
}
