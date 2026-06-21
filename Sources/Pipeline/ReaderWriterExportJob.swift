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
                self.removePartialOutputIfNeeded()
                self.setStatus(.failed)
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
        guard _status != .completed && _status != .cancelled && _status != .failed else {
            stateLock.unlock()
            return
        }
        isCancelled = true
        stateLock.unlock()
        reader?.cancelReading()
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
            guard reader.canAdd(output) else {
                throw VideoX.Error.videoTrackEmpty
            }
            reader.add(output)
            videoOutput = output

            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: abs(size.width), AVVideoHeightKey: abs(size.height)]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            input.transform = videoTrack.preferredTransform
            guard writer.canAdd(input) else {
                throw VideoX.Error.addVideoTrack
            }
            writer.add(input)
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
            guard reader.canAdd(output) else {
                throw VideoX.Error.error(NSError(domain: "Kakapos.ReaderWriterExportJob", code: -1001, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to attach audio reader output."
                ]))
            }
            reader.add(output)
            audioOutput = output
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw VideoX.Error.error(NSError(domain: "Kakapos.ReaderWriterExportJob", code: -1002, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to attach audio writer input."
                ]))
            }
            writer.add(input)
            audioInput = input
        }

        guard videoOutput != nil || audioOutput != nil else {
            throw VideoX.Error.videoTrackEmpty
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
        dispatchProgress(video: 0, audio: 0, hasVideo: hasVideo, hasAudio: hasAudio, finishWriting: 0)

        if let output = videoOutput, let input = videoInput {
            group.enter()
            encodeTrack(output: output, input: input, reader: reader, writer: writer, group: group, onSample: { buffer in
                videoProgress = (CMSampleBufferGetPresentationTimeStamp(buffer) - startTime).seconds / duration
                self.dispatchProgress(
                    video: videoProgress,
                    audio: audioProgress,
                    hasVideo: hasVideo,
                    hasAudio: hasAudio,
                    finishWriting: 0
                )
            }, onFailure: { error in
                exportError = exportError ?? error
            })
        }

        if let output = audioOutput, let input = audioInput {
            group.enter()
            encodeTrack(output: output, input: input, reader: reader, writer: writer, group: group, onSample: { buffer in
                audioProgress = (CMSampleBufferGetPresentationTimeStamp(buffer) - startTime).seconds / duration
                self.dispatchProgress(
                    video: videoProgress,
                    audio: audioProgress,
                    hasVideo: hasVideo,
                    hasAudio: hasAudio,
                    finishWriting: 0
                )
            }, onFailure: { error in
                exportError = exportError ?? error
            })
        }

        group.notify(queue: queue) {
            self.finishExport(
                reader: reader,
                writer: writer,
                hasVideo: hasVideo,
                hasAudio: hasAudio,
                lastVideoProgress: videoProgress,
                lastAudioProgress: audioProgress,
                exportError: exportError,
                completion: completion
            )
        }
    }

    private func encodeTrack(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        group: DispatchGroup,
        onSample: @escaping (CMSampleBuffer) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                guard self.waitUntilReadyForWork() else {
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if let runtimeError = self.runtimeErrorIfNeeded(reader: reader, writer: writer) {
                    onFailure(runtimeError)
                    input.markAsFinished()
                    group.leave()
                    return
                }
                guard let buffer = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    group.leave()
                    return
                }
                onSample(buffer)
                if !input.append(buffer) {
                    onFailure(writer.error ?? reader.error ?? VideoX.Error.unknown)
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }

    private func finishExport(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        hasVideo: Bool,
        hasAudio: Bool,
        lastVideoProgress: Double,
        lastAudioProgress: Double,
        exportError: Error?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if let finalError = resolvedTerminalError(reader: reader, writer: writer, exportError: exportError) {
            if case VideoX.Error.exportCancelled = VideoX.Error.toError(finalError) {
                removePartialOutputIfNeeded()
                setStatus(.cancelled)
            } else {
                removePartialOutputIfNeeded()
                setStatus(.failed)
            }
            DispatchQueue.main.async { completion(.failure(finalError)) }
            return
        }

        dispatchProgress(
            video: lastVideoProgress,
            audio: lastAudioProgress,
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            finishWriting: 0
        )
        writer.finishWriting {
            self.queue.async {
                if let finalError = self.resolvedTerminalError(reader: reader, writer: writer, exportError: writer.error) {
                    if case VideoX.Error.exportCancelled = VideoX.Error.toError(finalError) {
                        self.removePartialOutputIfNeeded()
                        self.setStatus(.cancelled)
                    } else {
                        self.removePartialOutputIfNeeded()
                        self.setStatus(.failed)
                    }
                    DispatchQueue.main.async { completion(.failure(finalError)) }
                    return
                }

                self.setStatus(.completed)
                self.dispatchProgress(
                    video: hasVideo ? 1 : 0,
                    audio: hasAudio ? 1 : 0,
                    hasVideo: hasVideo,
                    hasAudio: hasAudio,
                    finishWriting: 1
                )
                DispatchQueue.main.async {
                    completion(.success(self.outputURL))
                }
            }
        }
    }

    private func dispatchProgress(video: Double, audio: Double, hasVideo: Bool, hasAudio: Bool, finishWriting: Double) {
        DispatchQueue.main.async {
            self.progressHandler?(
                ProgressInfo(
                    videoProgress: video,
                    audioProgress: audio,
                    hasVideo: hasVideo,
                    hasAudio: hasAudio,
                    finishWritingProgress: finishWriting
                )
            )
        }
    }

    private var currentlyCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }

    private func runtimeErrorIfNeeded(reader: AVAssetReader, writer: AVAssetWriter) -> Error? {
        if currentlyCancelled || reader.status == .cancelled || writer.status == .cancelled {
            return VideoX.Error.exportCancelled
        }
        if reader.status == .failed {
            return reader.error ?? VideoX.Error.unknown
        }
        if writer.status == .failed {
            return writer.error ?? VideoX.Error.unknown
        }
        if writer.status != .writing {
            return writer.error ?? VideoX.Error.unknown
        }
        return nil
    }

    private func resolvedTerminalError(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        exportError: Error?
    ) -> Error? {
        if currentlyCancelled || reader.status == .cancelled || writer.status == .cancelled {
            return VideoX.Error.exportCancelled
        }
        if let exportError {
            return exportError
        }
        if reader.status == .failed {
            return reader.error ?? VideoX.Error.unknown
        }
        if writer.status == .failed {
            return writer.error ?? VideoX.Error.unknown
        }
        return nil
    }

    private func removePartialOutputIfNeeded() {
        try? FileManager.default.removeItem(at: outputURL)
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
        let didChange = _status != status
        _status = status
        if shouldSignal {
            stateLock.broadcast()
        }
        stateLock.unlock()
        guard didChange else { return }
        DispatchQueue.main.async {
            self.statusHandler?(status)
        }
    }

    func _setStatusForTesting(_ status: Status) {
        setStatus(status, shouldSignal: false)
    }
}
