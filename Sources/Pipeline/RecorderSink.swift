//
//  RecorderSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreVideo

public struct RecordedClip: Equatable {
    public let outputURL: URL
    public let duration: CMTime
    public let startedAt: CMTime?
    public let endedAt: CMTime?

    public init(outputURL: URL, duration: CMTime, startedAt: CMTime?, endedAt: CMTime?) {
        self.outputURL = outputURL
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public final class RecorderSink: MediaSink {
    public enum State {
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

    private let writer: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var pausedAt: CMTime?
    private var accumulatedPauseDuration: CMTime = .zero
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
                self.setState(.finished)
                let clip = RecordedClip(outputURL: self.outputURL, duration: .zero, startedAt: self.startTime, endedAt: self.lastPresentationTime)
                self.recordedClip = clip
                completion(.success(clip))
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            self.writer.finishWriting {
                self.setState(.finished)
                if let error = self.writer.error {
                    completion(.failure(error))
                } else {
                    let clip = self.makeRecordedClip()
                    self.recordedClip = clip
                    completion(.success(clip))
                }
            }
        }
    }

    public func cancel() {
        queue.async {
            self.writer.cancelWriting()
            self.setState(.cancelled)
            self.recordedClip = nil
        }
    }

    public func pauseRecording(at time: CMTime) {
        queue.sync {
            guard state == .recording else { return }
            pausedAt = time
            setState(.paused)
        }
    }

    public func pauseRecording() {
        queue.sync {
            guard state == .recording else { return }
            pausedAt = lastPresentationTime ?? startTime ?? .zero
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
            try normalizedPresentationTime(for: frame.metadata.presentationTime),
            sampleDuration: frame.metadata.duration
        )
        try startIfNeeded(at: normalizedTime)
        guard let input = videoInput, let adaptor = pixelBufferAdaptor, input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: normalizedTime)
        if !hasWrittenFirstVideoFrame {
            hasWrittenFirstVideoFrame = true
            try flushPendingLeadingAudioIfPossible()
        }
        updateLastPresentationTime(normalizedTime)
        if let startTime = startTime {
            durationChangedHandler?(normalizedTime - startTime)
        }
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
            try normalizedPresentationTime(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
            sampleDuration: CMSampleBufferGetDuration(sampleBuffer)
        )
        try startIfNeeded(at: normalizedTime)
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        var timingCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
        var timingInfo = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid), count: timingCount)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: timingCount, arrayToFill: &timingInfo, entriesNeededOut: &timingCount)
        timingInfo = timingInfo.map {
            let translatedPresentationTime = $0.presentationTimeStamp - accumulatedPauseDuration
            let translatedDecodeTime = $0.decodeTimeStamp.isValid ? ($0.decodeTimeStamp - accumulatedPauseDuration) : $0.decodeTimeStamp
            return CMSampleTimingInfo(duration: $0.duration, presentationTimeStamp: translatedPresentationTime, decodeTimeStamp: translatedDecodeTime)
        }
        var rebasedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &rebasedBuffer
        )
        input.append(rebasedBuffer ?? sampleBuffer)
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
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC], sourceFormatHint: CMSampleBufferGetFormatDescription(sampleBuffer))
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
            audioInput = input
        }
    }

    private func startIfNeeded(at time: CMTime) throws {
        guard state == .idle else { return }
        guard writer.startWriting() else { throw writer.error ?? VideoX.Error.unknown }
        writer.startSession(atSourceTime: time)
        startTime = time
        lastPresentationTime = time
        setState(.recording)
    }

    private func normalizedPresentationTime(for time: CMTime) throws -> CMTime {
        if let pausedAt, time.isValid, pausedAt.isValid {
            accumulatedPauseDuration = accumulatedPauseDuration + (time - pausedAt)
            self.pausedAt = nil
            setState(.recording)
        }
        return time - accumulatedPauseDuration
    }

    private func adjustedPresentationTime(_ time: CMTime, sampleDuration: CMTime?) -> CMTime {
        guard let lastPresentationTime, time <= lastPresentationTime else { return time }
        let minimumStep: CMTime
        if let sampleDuration, sampleDuration.isValid, sampleDuration > .zero {
            minimumStep = sampleDuration
        } else {
            minimumStep = CMTime(value: 1, timescale: 600)
        }
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

    private func makeRecordedClip() -> RecordedClip {
        let startedAt = startTime
        let endedAt = lastPresentationTime
        let duration: CMTime
        if let startedAt, let endedAt, startedAt.isValid, endedAt.isValid {
            duration = CMTimeSubtract(endedAt, startedAt)
        } else {
            duration = .zero
        }
        return RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        DispatchQueue.main.async {
            self.stateChangedHandler?(newState)
        }
    }
}
