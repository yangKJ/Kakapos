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
    public enum State: Equatable {
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

    public init(outputURL: URL, fileType: AVFileType = .mp4) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
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
}
