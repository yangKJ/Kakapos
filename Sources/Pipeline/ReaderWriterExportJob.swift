//
//  ReaderWriterExportJob.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public final class ReaderWriterExportJob {
    public enum Status {
        case idle
        case exporting
        case paused
        case completed
        case cancelled
    }

    public struct ProgressInfo {
        public var videoProgress: Double
        public var audioProgress: Double
        public var hasVideo: Bool
        public var hasAudio: Bool

        public init(videoProgress: Double, audioProgress: Double, hasVideo: Bool, hasAudio: Bool) {
            self.videoProgress = min(max(videoProgress, 0), 1)
            self.audioProgress = min(max(audioProgress, 0), 1)
            self.hasVideo = hasVideo
            self.hasAudio = hasAudio
        }

        public var fractionCompleted: Double {
            let activeCount = (hasVideo ? 1.0 : 0.0) + (hasAudio ? 1.0 : 0.0)
            guard activeCount > 0 else { return 0 }
            let total = (hasVideo ? videoProgress : 0) + (hasAudio ? audioProgress : 0)
            return total / activeCount
        }
    }

    public var status: Status {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _status
    }
    public var progressHandler: ((ProgressInfo) -> Void)?
    public var statusHandler: ((Status) -> Void)?

    private let asset: AVAsset
    private let outputURL: URL
    private let fileType: AVFileType
    private let timeRange: CMTimeRange?
    private let videoComposition: AVVideoComposition?
    private let audioMix: AVAudioMix?
    private let queue = DispatchQueue(label: "com.condy.kakapos.reader-writer-export")
    private let stateLock = NSCondition()
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var _status: Status = .idle
    private var isCancelled = false

    public init(
        asset: AVAsset,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil
    ) {
        self.asset = asset
        self.outputURL = outputURL
        self.fileType = fileType
        self.timeRange = timeRange
        self.videoComposition = videoComposition
        self.audioMix = audioMix
    }

    public func export(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            do {
                try self.exportOnQueue(completion: completion)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    public func pause() {
        transitionStatusIfNeeded(from: .exporting, to: .paused)
    }

    public func resume() {
        stateLock.lock()
        guard _status == .paused else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        setStatus(.exporting, shouldSignal: true)
    }

    public func cancel() {
        stateLock.lock()
        guard _status != .completed && _status != .cancelled else {
            stateLock.unlock()
            return
        }
        isCancelled = true
        stateLock.unlock()
        reader?.cancelReading()
        writer?.cancelWriting()
        setStatus(.cancelled, shouldSignal: true)
    }

    private func exportOnQueue(completion: @escaping (Result<URL, Error>) -> Void) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        self.reader = reader
        self.writer = writer
        if let timeRange, timeRange.isValid, !timeRange.isEmpty {
            reader.timeRange = timeRange
        }

        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        var videoOutput: AVAssetReaderOutput?
        var audioOutput: AVAssetReaderOutput?
        var videoInput: AVAssetWriterInput?
        var audioInput: AVAssetWriterInput?

        if let videoTrack = videoTracks.first {
            let outputSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let output: AVAssetReaderOutput
            if let videoComposition {
                let compositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: outputSettings)
                compositionOutput.videoComposition = videoComposition
                output = compositionOutput
            } else {
                output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            }
            if reader.canAdd(output) { reader.add(output) }
            videoOutput = output

            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: abs(size.width), AVVideoHeightKey: abs(size.height)]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            input.transform = videoTrack.preferredTransform
            if writer.canAdd(input) { writer.add(input) }
            videoInput = input
        }

        if let audioTrack = audioTracks.first {
            let output: AVAssetReaderOutput
            if let audioMix {
                let mixOutput = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: nil)
                mixOutput.audioMix = audioMix
                output = mixOutput
            } else {
                output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            }
            if reader.canAdd(output) { reader.add(output) }
            audioOutput = output
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input) }
            audioInput = input
        }

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? VideoX.Error.unknown
        }
        setStatus(.exporting)
        let startTime = timeRange?.start ?? .zero
        writer.startSession(atSourceTime: startTime)
        let group = DispatchGroup()
        let effectiveDuration = timeRange?.duration.seconds ?? asset.duration.seconds
        let duration = max(effectiveDuration, 0.001)
        var videoProgress = 0.0
        var audioProgress = 0.0
        let hasVideo = videoOutput != nil
        let hasAudio = audioOutput != nil
        var exportError: Error?
        dispatchProgress(video: 0, audio: 0, hasVideo: hasVideo, hasAudio: hasAudio)

        if let output = videoOutput, let input = videoInput {
            group.enter()
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard self.waitUntilReadyForWork() else {
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                    if let buffer = output.copyNextSampleBuffer() {
                        videoProgress = (CMSampleBufferGetPresentationTimeStamp(buffer) - startTime).seconds / duration
                        self.dispatchProgress(video: videoProgress, audio: audioProgress, hasVideo: hasVideo, hasAudio: hasAudio)
                        if !input.append(buffer) {
                            exportError = writer.error ?? reader.error ?? VideoX.Error.unknown
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    } else {
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        if let output = audioOutput, let input = audioInput {
            group.enter()
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard self.waitUntilReadyForWork() else {
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                    if let buffer = output.copyNextSampleBuffer() {
                        audioProgress = (CMSampleBufferGetPresentationTimeStamp(buffer) - startTime).seconds / duration
                        self.dispatchProgress(video: videoProgress, audio: audioProgress, hasVideo: hasVideo, hasAudio: hasAudio)
                        if !input.append(buffer) {
                            exportError = writer.error ?? reader.error ?? VideoX.Error.unknown
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    } else {
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        group.notify(queue: queue) {
            if self.currentlyCancelled {
                DispatchQueue.main.async { completion(.failure(VideoX.Error.exportCancelled)) }
                return
            }
            if let exportError {
                DispatchQueue.main.async { completion(.failure(exportError)) }
                return
            }
            writer.finishWriting {
                self.setStatus(.completed)
                self.dispatchProgress(video: hasVideo ? 1 : 0, audio: hasAudio ? 1 : 0, hasVideo: hasVideo, hasAudio: hasAudio)
                DispatchQueue.main.async {
                    if let error = writer.error {
                        completion(.failure(error))
                    } else {
                        completion(.success(self.outputURL))
                    }
                }
            }
        }
    }

    private func dispatchProgress(video: Double, audio: Double, hasVideo: Bool, hasAudio: Bool) {
        DispatchQueue.main.async {
            self.progressHandler?(ProgressInfo(videoProgress: video, audioProgress: audio, hasVideo: hasVideo, hasAudio: hasAudio))
        }
    }

    private var currentlyCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }

    private func waitUntilReadyForWork() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        while _status == .paused && !isCancelled {
            stateLock.wait()
        }
        return !isCancelled
    }

    private func transitionStatusIfNeeded(from expectedStatus: Status, to newStatus: Status) {
        stateLock.lock()
        guard _status == expectedStatus else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        setStatus(newStatus)
    }

    private func setStatus(_ status: Status, shouldSignal: Bool = false) {
        stateLock.lock()
        _status = status
        if shouldSignal {
            stateLock.broadcast()
        }
        stateLock.unlock()
        DispatchQueue.main.async {
            self.statusHandler?(status)
        }
    }
}
