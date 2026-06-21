//
//  VideoAssetExportSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

final class VideoAssetExportSession {

    struct Configuration {
        var fileType: AVFileType
        var shouldOptimizeForNetworkUse: Bool = true
        var videoSettings: [String: Any]
        var audioSettings: [String: Any]
        var timeRange: CMTimeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        var metadata: [AVMetadataItem] = []
        var videoComposition: AVVideoComposition?
        var audioMix: AVAudioMix?
        var videoProcessors: [FrameProcessor] = []
    }

    enum Status: Equatable {
        case idle
        case exporting
        case paused
        case completed
        case cancelled
        case failed
    }

    enum SessionError: Error {
        case noTracks
        case cannotAddVideoOutput
        case cannotAddVideoInput
        case cannotAddAudioOutput
        case cannotAddAudioInput
        case cannotStartWriting
        case cannotStartReading
        case invalidStatus
        case cancelled
    }

    final class ExportProgress {
        let videoProgress: Progress?
        let audioProgress: Progress?
        let finishWritingProgress: Progress

        private let childProgressTotalUnitCount: Int64 = 10_000

        init(tracksAudioEncoding: Bool, tracksVideoEncoding: Bool) {
            finishWritingProgress = Progress(totalUnitCount: childProgressTotalUnitCount)
            audioProgress = tracksAudioEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
            videoProgress = tracksVideoEncoding ? Progress(totalUnitCount: childProgressTotalUnitCount) : nil
        }

        var fractionCompleted: Double {
            let parts = [videoProgress, audioProgress, finishWritingProgress]
            let active = parts.compactMap { $0 }
            guard !active.isEmpty else { return 0 }
            return active.map(\.fractionCompleted).reduce(0, +) / Double(active.count)
        }

        func updateVideoEncodingProgress(fractionCompleted: Double) {
            videoProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }

        func updateAudioEncodingProgress(fractionCompleted: Double) {
            audioProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }

        func updateFinishWritingProgress(fractionCompleted: Double) {
            finishWritingProgress.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }
    }

    private let asset: AVAsset
    private let configuration: Configuration
    private let outputURL: URL
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderOutput?
    private let audioOutput: AVAssetReaderAudioMixOutput?
    private let videoInput: AVAssetWriterInput?
    private let audioInput: AVAssetWriterInput?
    private let videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let queue = DispatchQueue(label: "com.condy.kakapos.video-asset-export")
    private let duration: CMTime

    private let pauseDispatchGroup = DispatchGroup()
    private var cancelled = false
    private(set) var status: Status = .idle
    private var progress: ExportProgress?
    private var progressHandler: ((ExportProgress) -> Void)?
    private var statusHandler: ((Status) -> Void)?
    private var processorError: Error?

    init(asset: AVAsset, outputURL: URL, configuration: Configuration) throws {
        self.asset = asset.copy() as! AVAsset
        self.configuration = configuration
        self.outputURL = outputURL
        self.reader = try AVAssetReader(asset: self.asset)
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.fileType)
        self.reader.timeRange = configuration.timeRange
        self.writer.shouldOptimizeForNetworkUse = configuration.shouldOptimizeForNetworkUse
        self.writer.metadata = configuration.metadata

        if configuration.timeRange.duration.isValid && !configuration.timeRange.duration.isPositiveInfinity {
            self.duration = configuration.timeRange.duration
        } else {
            self.duration = self.asset.duration
        }

        let videoTracks = self.asset.tracks(withMediaType: .video)
        if videoTracks.count > 0 {
            let output: AVAssetReaderOutput
            let inputTransform: CGAffineTransform?
            if let videoComposition = configuration.videoComposition {
                let compositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
                compositionOutput.alwaysCopiesSampleData = false
                compositionOutput.videoComposition = videoComposition
                output = compositionOutput
                inputTransform = nil
            } else {
                let trackOutput = AVAssetReaderTrackOutput(
                    track: videoTracks.first!,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]]
                )
                trackOutput.alwaysCopiesSampleData = false
                output = trackOutput
                inputTransform = videoTracks.first!.preferredTransform
            }
            guard reader.canAdd(output) else {
                throw SessionError.cannotAddVideoOutput
            }
            reader.add(output)
            videoOutput = output

            let input: AVAssetWriterInput
            let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
            if let transform = inputTransform {
                let size = CGSize(
                    width: configuration.videoSettings[AVVideoWidthKey] as? CGFloat ?? 0,
                    height: configuration.videoSettings[AVVideoHeightKey] as? CGFloat ?? 0
                )
                let transformedSize = size.applying(transform.inverted())
                var settings = configuration.videoSettings
                settings[AVVideoWidthKey] = abs(transformedSize.width)
                settings[AVVideoHeightKey] = abs(transformedSize.height)
                input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.transform = transform
            } else {
                input = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
            }
            input.expectsMediaDataInRealTime = false
            if configuration.videoProcessors.isEmpty {
                pixelBufferAdaptor = nil
            } else {
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: configuration.videoSettings[AVVideoWidthKey] as? CGFloat ?? 0,
                        kCVPixelBufferHeightKey as String: configuration.videoSettings[AVVideoHeightKey] as? CGFloat ?? 0
                    ]
                )
            }
            guard writer.canAdd(input) else {
                throw SessionError.cannotAddVideoInput
            }
            writer.add(input)
            videoInput = input
            videoPixelBufferAdaptor = pixelBufferAdaptor
        } else {
            videoOutput = nil
            videoInput = nil
            videoPixelBufferAdaptor = nil
        }

        let audioTracks = self.asset.tracks(withMediaType: .audio)
        if audioTracks.count > 0 {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            output.alwaysCopiesSampleData = false
            output.audioMix = configuration.audioMix
            guard reader.canAdd(output) else {
                throw SessionError.cannotAddAudioOutput
            }
            reader.add(output)
            audioOutput = output

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: configuration.audioSettings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw SessionError.cannotAddAudioInput
            }
            writer.add(input)
            audioInput = input
        } else {
            audioOutput = nil
            audioInput = nil
        }

        if videoTracks.isEmpty && audioTracks.isEmpty {
            throw SessionError.noTracks
        }
    }

    func export(
        progress: ((ExportProgress) -> Void)?,
        status: ((Status) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) {
        guard self.status == .idle, cancelled == false else {
            DispatchQueue.main.async {
                completion(SessionError.invalidStatus)
            }
            return
        }

        do {
            guard writer.startWriting() else {
                throw writer.error ?? SessionError.cannotStartWriting
            }
            guard reader.startReading() else {
                throw reader.error ?? SessionError.cannotStartReading
            }
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
            return
        }

        self.status = .exporting
        self.statusHandler = status
        self.progressHandler = progress
        self.progress = ExportProgress(
            tracksAudioEncoding: audioInput != nil,
            tracksVideoEncoding: videoInput != nil
        )
        dispatchStatus(.exporting)
        writer.startSession(atSourceTime: configuration.timeRange.start)

        var videoCompleted = false
        var audioCompleted = false

        if let videoInput, let videoOutput {
            var strongSession: VideoAssetExportSession? = self
            videoInput.requestMediaDataWhenReady(on: queue) { [unowned videoInput] in
                guard let session = strongSession else { return }
                if !session.encode(from: videoOutput, to: videoInput) {
                    videoCompleted = true
                    strongSession = nil
                    if audioCompleted {
                        session.finish(completionHandler: completion)
                    }
                }
            }
        } else {
            videoCompleted = true
        }

        if let audioInput, let audioOutput {
            var strongSession: VideoAssetExportSession? = self
            audioInput.requestMediaDataWhenReady(on: queue) { [unowned audioInput] in
                guard let session = strongSession else { return }
                if !session.encode(from: audioOutput, to: audioInput) {
                    audioCompleted = true
                    strongSession = nil
                    if videoCompleted {
                        session.finish(completionHandler: completion)
                    }
                }
            }
        } else {
            audioCompleted = true
        }
    }

    func pause() {
        guard status == .exporting, cancelled == false else { return }
        status = .paused
        pauseDispatchGroup.enter()
        dispatchStatus(.paused)
    }

    func resume() {
        guard status == .paused, cancelled == false else { return }
        status = .exporting
        pauseDispatchGroup.leave()
        dispatchStatus(.exporting)
    }

    func cancel() {
        if status == .paused {
            resume()
        }
        guard status == .exporting, cancelled == false else { return }
        cancelled = true
        status = .cancelled
        dispatchStatus(.cancelled)
        queue.async {
            if self.reader.status == .reading {
                self.reader.cancelReading()
            }
        }
    }

    private func encode(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) -> Bool {
        while input.isReadyForMoreMediaData {
            if let processorError {
                self.processorError = processorError
                input.markAsFinished()
                reader.cancelReading()
                return false
            }
            if reader.status != .reading || writer.status != .writing {
                input.markAsFinished()
                return false
            }
            pauseDispatchGroup.wait()

            if let buffer = output.copyNextSampleBuffer() {
                let progress = (CMSampleBufferGetPresentationTimeStamp(buffer) - configuration.timeRange.start).seconds / max(duration.seconds, 0.001)
                if videoOutput === output {
                    dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: progress) }
                }
                if audioOutput === output {
                    dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: progress) }
                }
                if videoOutput === output, !configuration.videoProcessors.isEmpty {
                    switch appendProcessedVideoSampleBuffer(buffer, to: input) {
                    case .success(let appended):
                        if !appended {
                            input.markAsFinished()
                            reader.cancelReading()
                            return false
                        }
                    case .failure(let error):
                        processorError = error
                        input.markAsFinished()
                        reader.cancelReading()
                        return false
                    }
                } else if !input.append(buffer) {
                    input.markAsFinished()
                    return false
                }
            } else {
                if videoOutput === output {
                    dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: 1) }
                }
                if audioOutput === output {
                    dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: 1) }
                }
                input.markAsFinished()
                return false
            }
        }
        return true
    }

    private func finish(completionHandler: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))

        if let processorError {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            dispatchCallback(with: processorError, completionHandler)
            return
        }

        if reader.status == .cancelled || writer.status == .cancelled {
            if writer.status != .cancelled {
                writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: outputURL)
            dispatchCallback(with: SessionError.cancelled, completionHandler)
            return
        }

        if writer.status == .failed {
            try? FileManager.default.removeItem(at: outputURL)
            dispatchCallback(with: writer.error, completionHandler)
        } else if reader.status == .failed {
            try? FileManager.default.removeItem(at: outputURL)
            writer.cancelWriting()
            dispatchCallback(with: reader.error, completionHandler)
        } else {
            writer.finishWriting {
                self.queue.async {
                    if self.writer.status == .failed {
                        try? FileManager.default.removeItem(at: self.outputURL)
                        self.dispatchCallback(with: self.writer.error, completionHandler)
                    } else {
                        self.dispatchProgressCallback { $0.updateFinishWritingProgress(fractionCompleted: 1) }
                        self.dispatchCallback(with: nil, completionHandler)
                    }
                }
            }
        }
    }

    private func appendProcessedVideoSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput
    ) -> Result<Bool, Error> {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return .success(input.append(sampleBuffer))
        }

        let metadata = FrameMetadata(
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer).isValid ? CMSampleBufferGetDuration(sampleBuffer) : nil,
            sourceTime: CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        )
        let frame = MediaFrame(sampleBuffer: sampleBuffer, metadata: metadata)
        let processedResult = processVideoFrame(frame)

        switch processedResult {
        case .failure(let error):
            return .failure(error)
        case .success(let processedFrame):
            guard let adaptor = videoPixelBufferAdaptor else {
                return .success(input.append(processedFrame.sampleBuffer ?? sampleBuffer))
            }
            guard let processedPixelBuffer = processedFrame.pixelBuffer ?? CMSampleBufferGetImageBuffer(processedFrame.sampleBuffer ?? sampleBuffer) else {
                return .success(false)
            }
            let presentationTime = processedFrame.metadata.presentationTime
            return .success(adaptor.append(processedPixelBuffer, withPresentationTime: presentationTime))
        }
    }

    private func processVideoFrame(_ frame: MediaFrame) -> Result<MediaFrame, Error> {
        guard !configuration.videoProcessors.isEmpty else {
            return .success(frame)
        }

        var currentFrame = frame
        for processor in configuration.videoProcessors {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<MediaFrame, Error>?
            processor.process(currentFrame) { output in
                result = output
                semaphore.signal()
            }
            semaphore.wait()
            switch result {
            case .success(let processedFrame):
                currentFrame = processedFrame
            case .failure(let error):
                return .failure(error)
            case .none:
                return .failure(SessionError.invalidStatus)
            }
        }
        return .success(currentFrame)
    }

    private func dispatchProgressCallback(with updater: @escaping (ExportProgress) -> Void) {
        DispatchQueue.main.async {
            guard let progress = self.progress else { return }
            updater(progress)
            self.progressHandler?(progress)
        }
    }

    private func dispatchStatus(_ status: Status) {
        DispatchQueue.main.async {
            self.statusHandler?(status)
        }
    }

    private func dispatchCallback(with error: Error?, _ completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            self.progressHandler = nil
            self.status = error == nil ? .completed : (self.cancelled ? .cancelled : .failed)
            self.dispatchStatus(self.status)
            completionHandler(error)
        }
    }
}
