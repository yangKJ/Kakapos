//
//  RecorderSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreVideo

public final class RecorderSink: MediaSink {
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
        public let lastPresentationTime: CMTime?
        public let pausedAt: CMTime?

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

        public var summaryText: String {
            let durationText = String(format: "%.2fs", totalDuration.seconds)
            let currentClipText = String(format: "%.2fs", currentClipDuration.seconds)
            var text = "state \(state) · clips \(clipCount) · total \(durationText) · clip \(currentClipText) · recorded \(hasRecordedClip ? "yes" : "no")"
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let pausedAt {
                text += " · pausedAt \(String(format: "%.2fs", pausedAt.seconds))"
            }
            return text
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case recording
        case paused
        case finished
        case cancelled
    }

    public let outputURL: URL
    public private(set) var state: State = .idle
    public private(set) var recordedClip: RecordedClip?
    public var durationChangedHandler: ((CMTime) -> Void)?
    public var stateChangedHandler: ((State) -> Void)?
    public var droppedFrameHandler: ((FrameMetadata) -> Void)?
    public var runtimeErrorHandler: ((Error) -> Void)?
    public var snapshot: Snapshot {
        queue.sync {
            let recordingSnapshot = session.snapshot()
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
                lastPresentationTime: lastPresentationTime,
                pausedAt: pausedAt
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
            pausedAt: currentSnapshot.pausedAt
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    private let writer: AVAssetWriter
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
    private let queue = DispatchQueue(label: "com.condy.kakapos.recorder-sink")
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true

    public init(outputURL: URL, fileType: AVFileType = .mp4) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard canAcceptFrames() else {
            completion(.success(()))
            return
        }
        queue.async {
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
            if self.state == .cancelled {
                completion(.failure(VideoX.Error.exportCancelled))
                return
            }
            if self.state == .finished, let recordedClip = self.recordedClip {
                completion(.success(recordedClip))
                return
            }
            guard self.state == .recording || self.state == .paused else {
                self.session.finalizeCurrentClipIfNeeded()
                self.setState(.finished)
                let clip = self.session.makeRecordedClip(
                    outputURL: self.outputURL,
                    fallbackStartedAt: self.startTime,
                    fallbackEndedAt: self.lastPresentationTime
                )
                self.recordedClip = clip
                completion(.success(clip))
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            self.writer.finishWriting {
                self.session.finalizeCurrentClipIfNeeded()
                if self.state == .paused, let lastPresentationTime = self.lastPresentationTime {
                    self.session.trimLastClipEndingIfNeeded(to: lastPresentationTime)
                }
                self.setState(.finished)
                if let error = self.writer.error {
                    self.runtimeErrorHandler?(error)
                    completion(.failure(error))
                } else {
                    let clip = self.session.makeRecordedClip(
                        outputURL: self.outputURL,
                        fallbackStartedAt: self.startTime,
                        fallbackEndedAt: self.lastPresentationTime
                    )
                    self.recordedClip = clip
                    completion(.success(clip))
                }
            }
        }
    }

    public func cancel() {
        rejectFurtherFrames()
        queue.async {
            self.writer.cancelWriting()
            try? FileManager.default.removeItem(at: self.outputURL)
            self.setState(.cancelled)
            self.recordedClip = nil
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
        if let sampleBuffer = frame.sampleBuffer, CMSampleBufferGetImageBuffer(sampleBuffer) == nil {
            try appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = frame.pixelBuffer else { return }
        try setupVideoIfNeeded(pixelBuffer: pixelBuffer)
        let normalizedTime = adjustedPresentationTime(
            normalizedPresentationTime(for: frame.metadata.presentationTime),
            sampleDuration: frame.metadata.duration,
            applyPadding: applyPaddingAfterResume
        )
        try startIfNeeded(at: normalizedTime)
        guard let adaptor = pixelBufferAdaptor else { return }
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
    }

    private func setupVideoIfNeeded(pixelBuffer: CVPixelBuffer) throws {
        guard videoInput == nil else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw VideoX.Error.addVideoTrack }
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
        guard let input = audioInput else { return }
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

    private func setupAudioIfNeeded(sampleBuffer: CMSampleBuffer) throws {
        guard audioInput == nil else { return }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC],
            sourceFormatHint: CMSampleBufferGetFormatDescription(sampleBuffer)
        )
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
            audioInput = input
        }
    }

    private func startIfNeeded(at time: CMTime) throws {
        guard state == .idle || state == .paused else { return }
        if state == .idle {
            guard writer.startWriting() else { throw writer.error ?? VideoX.Error.unknown }
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
}
