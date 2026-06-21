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
        case finished
        case cancelled
    }

    public let outputURL: URL
    public private(set) var state: State = .idle
    public private(set) var recordedClip: RecordedClip?
    public var durationChangedHandler: ((CMTime) -> Void)?

    private let writer: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var lastPresentationTime: CMTime?
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
            guard self.state == .recording else {
                self.state = .finished
                let clip = RecordedClip(outputURL: self.outputURL, duration: .zero, startedAt: self.startTime, endedAt: self.lastPresentationTime)
                self.recordedClip = clip
                completion(.success(clip))
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            self.writer.finishWriting {
                self.state = .finished
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
            self.state = .cancelled
            self.recordedClip = nil
        }
    }

    private func consumeOnQueue(_ frame: MediaFrame) throws {
        if let sampleBuffer = frame.sampleBuffer, CMSampleBufferGetImageBuffer(sampleBuffer) == nil {
            try appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = frame.pixelBuffer else { return }
        try setupVideoIfNeeded(pixelBuffer: pixelBuffer)
        try startIfNeeded(at: frame.metadata.presentationTime)
        guard let input = videoInput, let adaptor = pixelBufferAdaptor, input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: frame.metadata.presentationTime)
        updateLastPresentationTime(frame.metadata.presentationTime)
        if let startTime = startTime {
            durationChangedHandler?(frame.metadata.presentationTime - startTime)
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
        try startIfNeeded(at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
        updateLastPresentationTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
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
        state = .recording
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
}
