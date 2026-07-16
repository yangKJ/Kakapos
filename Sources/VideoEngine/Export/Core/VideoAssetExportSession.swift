//
//  VideoAssetExportSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

final class VideoAssetExportSession: @unchecked Sendable {

    private struct UnsafeSendableBox<T>: @unchecked Sendable {
        let value: T
    }

    struct Configuration {
        enum VideoEncodingStrategy {
            case automatic
            case encoded
            case passthrough
        }

        var fileType: AVFileType
        var shouldOptimizeForNetworkUse: Bool = true
        var videoSettings: [String: Any]
        var audioSettings: [String: Any]
        var timeRange: CMTimeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        var metadata: [AVMetadataItem] = []
        var videoComposition: AVVideoComposition?
        var audioMix: AVAudioMix?
        var videoProcessors: [FrameProcessor] = []
        var videoEncodingStrategy: VideoEncodingStrategy = .automatic
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
        case missingVideoFormatDescription
        case missingAudioFormatDescription
        case cannotStartWriting
        case cannotStartReading
        case invalidStatus
        case cancelled
    }

    final class ExportProgress {
        let videoProgress: Progress?
        let audioProgress: Progress?
        let finishWritingProgress: Progress
        private(set) var phase: ReaderWriterExportJob.ProgressInfo.Phase = .idle

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
            phase = .videoEncoding
            videoProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }

        func updateAudioEncodingProgress(fractionCompleted: Double) {
            phase = .audioEncoding
            audioProgress?.completedUnitCount = Int64(Double(childProgressTotalUnitCount) * fractionCompleted)
        }

        func updateFinishWritingProgress(fractionCompleted: Double) {
            phase = .finishing
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
        try Self.prepareOutputURL(outputURL)
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
        if let primaryVideoTrack = videoTracks.first {
            let output: AVAssetReaderOutput
            let inputTransform: CGAffineTransform?
            guard let sourceFormatHint = Self.makeFormatDescription(from: primaryVideoTrack.formatDescriptions) else {
                throw SessionError.missingVideoFormatDescription
            }
            let readerVideoComposition = configuration.videoComposition ?? Self.makeReaderVideoComposition(
                from: self.asset,
                videoTracks: videoTracks,
                shouldUseVideoProcessorPath: !configuration.videoProcessors.isEmpty
            )
            if let videoComposition = readerVideoComposition {
                let compositionOutput = AVAssetReaderVideoCompositionOutput(
                    videoTracks: videoTracks,
                    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                )
                compositionOutput.alwaysCopiesSampleData = false
                compositionOutput.videoComposition = videoComposition
                output = compositionOutput
                inputTransform = nil
            } else {
                let trackOutput = AVAssetReaderTrackOutput(
                    track: primaryVideoTrack,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]]
                )
                trackOutput.alwaysCopiesSampleData = false
                output = trackOutput
                inputTransform = primaryVideoTrack.preferredTransform
            }
            guard reader.canAdd(output) else {
                throw SessionError.cannotAddVideoOutput
            }
            reader.add(output)
            videoOutput = output

            let input: AVAssetWriterInput
            let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
            let usePassthrough = configuration.videoEncodingStrategy == .passthrough
                || (configuration.videoEncodingStrategy == .automatic
                    && !configuration.videoProcessors.isEmpty
                    && !writer.canApply(outputSettings: configuration.videoSettings, forMediaType: .video))

            if !usePassthrough, let transform = inputTransform {
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
            } else if !usePassthrough {
                input = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
            } else {
                input = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: nil,
                    sourceFormatHint: sourceFormatHint
                )
                if let transform = inputTransform {
                    input.transform = transform
                }
            }
            input.expectsMediaDataInRealTime = false
            if configuration.videoProcessors.isEmpty || usePassthrough {
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

            let audioTrack = audioTracks[0]
            guard let audioFormatDescription = Self.makeFormatDescription(from: audioTrack.formatDescriptions) else {
                throw SessionError.missingAudioFormatDescription
            }

            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: configuration.audioSettings,
                sourceFormatHint: audioFormatDescription
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                let passthroughInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: nil,
                    sourceFormatHint: audioFormatDescription
                )
                passthroughInput.expectsMediaDataInRealTime = false
                guard writer.canAdd(passthroughInput) else {
                    throw SessionError.cannotAddAudioInput
                }
                writer.add(passthroughInput)
                audioInput = passthroughInput
            }
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
            let box = UnsafeSendableBox(value: completion)
            DispatchQueue.main.async {
                box.value(SessionError.invalidStatus)
            }
            return
        }

        do {
            guard writer.startWriting() else {
                if Self.shouldFallbackToPassthrough(error: writer.error, configuration: configuration) {
                    try self.exportWithPassthroughFallback(
                        progress: progress,
                        status: status,
                        completion: completion
                    )
                    return
                }
                throw writer.error ?? SessionError.cannotStartWriting
            }
            guard reader.startReading() else {
                throw reader.error ?? SessionError.cannotStartReading
            }
        } catch {
            let box = UnsafeSendableBox(value: completion)
            DispatchQueue.main.async {
                box.value(error)
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
        let frame = SampleBufferFrame(sampleBuffer: sampleBuffer, metadata: metadata)
        let processedResult = processVideoFrame(frame)

        switch processedResult {
        case .failure(let error):
            return .failure(error)
        case .success(let processedFrame):
            guard let adaptor = videoPixelBufferAdaptor else {
                let sampleBufferBox = UnsafeSendableBox(value: processedFrame)
                return .success(input.append(extractSampleBuffer(sampleBufferBox.value) ?? sampleBuffer))
            }
            let processedBox = UnsafeSendableBox(value: processedFrame)
            let sampleBufferBox2 = UnsafeSendableBox(value: sampleBuffer)
            guard let processedPixelBuffer = extractPixelBuffer(processedBox.value) ?? CMSampleBufferGetImageBuffer(extractSampleBuffer(processedBox.value) ?? sampleBufferBox2.value) else {
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
        let box = UnsafeSendableBox(value: updater)
        let progressBox = UnsafeSendableBox(value: self.progress)
        DispatchQueue.main.async {
            guard let progress = progressBox.value else { return }
            box.value(progress)
            self.progressHandler?(progress)
        }
    }

    private func dispatchStatus(_ status: Status) {
        DispatchQueue.main.async { [self] in
            self.statusHandler?(status)
        }
    }

    private func dispatchCallback(with error: Error?, _ completionHandler: @escaping (Error?) -> Void) {
        let box = UnsafeSendableBox(value: completionHandler)
        DispatchQueue.main.async { [self] in
            self.progressHandler = nil
            self.status = error == nil ? .completed : (self.cancelled ? .cancelled : .failed)
            self.dispatchStatus(self.status)
            box.value(error)
        }
    }

    private func exportWithPassthroughFallback(
        progress: ((ExportProgress) -> Void)?,
        status: ((Status) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) throws {
        guard configuration.videoEncodingStrategy == .automatic, !configuration.videoProcessors.isEmpty else {
            throw writer.error ?? SessionError.cannotStartWriting
        }
        var fallbackConfiguration = configuration
        fallbackConfiguration.videoEncodingStrategy = .passthrough
        let fallbackSession = try VideoAssetExportSession(asset: asset, outputURL: outputURL, configuration: fallbackConfiguration)
        fallbackSession.export(progress: progress, status: status, completion: completion)
    }

    private static func shouldFallbackToPassthrough(error: Error?, configuration: Configuration) -> Bool {
        guard configuration.videoEncodingStrategy == .automatic, !configuration.videoProcessors.isEmpty else {
            return false
        }
        let nsError = error as NSError?
        return nsError?.domain == AVFoundationErrorDomain && nsError?.code == -11834
    }

    private static func makeReaderVideoComposition(
        from asset: AVAsset,
        videoTracks: [AVAssetTrack],
        shouldUseVideoProcessorPath: Bool
    ) -> AVVideoComposition? {
        guard shouldUseVideoProcessorPath else {
            return nil
        }
        guard #available(macOS 10.14, iOS 11.0, tvOS 11.0, watchOS 4.0, *) else {
            return nil
        }
        guard videoTracks.isEmpty == false else {
            return nil
        }
        return AVMutableVideoComposition(propertiesOf: asset)
    }

    private static func makeFormatDescription(from descriptions: [Any]) -> CMFormatDescription? {
        guard let first = descriptions.first else {
            return nil
        }
        let object = first as AnyObject
        guard CFGetTypeID(object) == CMFormatDescriptionGetTypeID() else {
            return nil
        }
        return unsafeBitCast(object, to: CMFormatDescription.self)
    }

    private static func prepareOutputURL(_ outputURL: URL) throws {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            throw error
        }
    }
}

extension VideoAssetExportSession: ReaderWriterExportSession {}
