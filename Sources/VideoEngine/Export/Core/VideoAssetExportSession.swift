//
//  VideoAssetExportSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
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
        var videoFrameProcessingTimeout: TimeInterval? = nil
        var videoEncodingStrategy: VideoEncodingStrategy = .automatic
        var performanceAccumulator = ReaderWriterExportPerformanceAccumulator()
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
        case cannotStartWriting
        case cannotStartReading
        case processedVideoAdaptorUnavailable
        case processedVideoFrameUnavailable
        case noProcessedVideoFrames
        case videoFrameProcessingTimedOut(seconds: TimeInterval)
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

        func makeSnapshot() -> ExportProgress {
            let snapshot = ExportProgress(
                tracksAudioEncoding: audioProgress != nil,
                tracksVideoEncoding: videoProgress != nil
            )
            snapshot.videoProgress?.completedUnitCount = videoProgress?.completedUnitCount ?? 0
            snapshot.audioProgress?.completedUnitCount = audioProgress?.completedUnitCount ?? 0
            snapshot.finishWritingProgress.completedUnitCount = finishWritingProgress.completedUnitCount
            snapshot.phase = phase
            return snapshot
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
    private let processorQueue = DispatchQueue(
        label: "com.condy.kakapos.video-asset-export.processing",
        qos: .userInitiated
    )
    private let videoProcessingOperationLock = NSLock()
    private let duration: CMTime

    private struct PendingProcessedVideoFrame {
        let pixelBuffer: CVPixelBuffer
        let presentationTime: CMTime
    }

    private struct VideoProcessingTiming: Sendable {
        let submittedAt: UInt64
        let queueDelayNanoseconds: UInt64
        let executionDurationNanoseconds: UInt64
        let callbackCompletedAt: UInt64
    }

    private var cancelled = false
    private(set) var status: Status = .idle
    private var progress: ExportProgress?
    private var progressHandler: ((ExportProgress) -> Void)?
    private var pendingProgressSnapshot: ExportProgress?
    private var progressDeliveryTimer: DispatchSourceTimer?
    private var statusHandler: ((Status) -> Void)?
    private var completionHandler: ((Error?) -> Void)?
    private var processorError: Error?
    private var processedVideoFrameCount = 0
    private var videoCompleted = false
    private var audioCompleted = false
    private var videoProcessingInFlight = false
    private var videoProcessingGeneration: UInt64 = 0
    private var videoProcessingTimeoutTimer: DispatchSourceTimer?
    private var videoProcessingOperation: FrameProcessingOperation?
    private var videoProcessingOperationToken: UInt64 = 0
    private var pendingProcessedVideoFrame: PendingProcessedVideoFrame?
    private var didBeginFinishing = false
    private var didDeliverCallback = false
    private var lifecycleRetain: VideoAssetExportSession?

    private static let maximumSamplesPerPump = 32
    private static let progressDeliveryInterval: TimeInterval = 0.1

    init(asset: AVAsset, outputURL: URL, configuration: Configuration) throws {
        self.asset = (asset.copy() as? AVAsset) ?? asset
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
            // 整体逐帧滤镜不应为了拿到 BGRA 帧而隐式创建视频合成。
            // 部分来自屏幕录制或照片图库的合法 H.264 素材会被这条隐式合成路径
            // 判为 invalidSourceMedia；直接读取轨道并把 preferredTransform 写回输出即可。
            let readerVideoComposition = configuration.videoComposition
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
                let outputSettings: [String: Any]
                if configuration.videoProcessors.isEmpty {
                    outputSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: [
                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            kCVPixelFormatType_32BGRA,
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        ]
                    ]
                } else {
                    outputSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                }
                let trackOutput = AVAssetReaderTrackOutput(
                    track: primaryVideoTrack,
                    outputSettings: outputSettings
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
            let processedPixelBufferSize: CGSize?
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
                processedPixelBufferSize = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
            } else if !usePassthrough {
                input = AVAssetWriterInput(mediaType: .video, outputSettings: configuration.videoSettings)
                processedPixelBufferSize = CGSize(
                    width: configuration.videoSettings[AVVideoWidthKey] as? CGFloat ?? 0,
                    height: configuration.videoSettings[AVVideoHeightKey] as? CGFloat ?? 0
                )
            } else {
                input = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: nil,
                    sourceFormatHint: sourceFormatHint
                )
                if let transform = inputTransform {
                    input.transform = transform
                }
                processedPixelBufferSize = nil
            }
            input.expectsMediaDataInRealTime = false
            if configuration.videoProcessors.isEmpty || usePassthrough {
                pixelBufferAdaptor = nil
            } else {
                guard let processedPixelBufferSize else {
                    throw SessionError.processedVideoAdaptorUnavailable
                }
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: processedPixelBufferSize.width,
                        kCVPixelBufferHeightKey as String: processedPixelBufferSize.height
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

            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: configuration.audioSettings
            )
            input.expectsMediaDataInRealTime = false
            // AVAssetReaderAudioMixOutput(nil) 输出的是方便编码的未压缩 PCM，
            // 不能把原始 AAC 轨道的 format description 当成这些样本的 source hint。
            // 否则 Writer 会在首批音频样本处把合法素材判为 invalidSourceMedia。
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
            configuration.performanceAccumulator.markFinal()
            let box = UnsafeSendableBox(value: completion)
            DispatchQueue.main.async {
                box.value(error)
            }
            return
        }

        self.status = .exporting
        configuration.performanceAccumulator.markStarted()
        self.statusHandler = status
        self.progressHandler = progress
        self.completionHandler = completion
        lifecycleRetain = self
        self.progress = ExportProgress(
            tracksAudioEncoding: audioInput != nil,
            tracksVideoEncoding: videoInput != nil
        )
        videoCompleted = videoInput == nil
        audioCompleted = audioInput == nil
        dispatchStatus(.exporting)
        writer.startSession(atSourceTime: configuration.timeRange.start)

        if let videoInput, let videoOutput {
            videoInput.requestMediaDataWhenReady(on: queue) { [weak self, unowned videoInput] in
                self?.pumpVideo(from: videoOutput, to: videoInput)
            }
        }

        if let audioInput, let audioOutput {
            audioInput.requestMediaDataWhenReady(on: queue) { [weak self, unowned audioInput] in
                self?.pumpAudio(from: audioOutput, to: audioInput)
            }
        }

        queue.async { [weak self] in
            self?.finishIfPossible()
        }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self, self.status == .exporting, self.cancelled == false, self.didBeginFinishing == false else { return }
            self.status = .paused
            self.dispatchStatus(.paused)
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, self.status == .paused, self.cancelled == false, self.didBeginFinishing == false else { return }
            self.status = .exporting
            self.dispatchStatus(.exporting)
            if let videoOutput = self.videoOutput, let videoInput = self.videoInput {
                self.pumpVideo(from: videoOutput, to: videoInput)
            }
            if let audioOutput = self.audioOutput, let audioInput = self.audioInput {
                self.pumpAudio(from: audioOutput, to: audioInput)
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self,
                  (self.status == .exporting || self.status == .paused),
                  self.cancelled == false else { return }
            self.cancelled = true
            self.status = .cancelled
            self.videoProcessingInFlight = false
            self.cancelVideoProcessingOperation()
            self.cancelVideoProcessingTimeout()
            self.dispatchStatus(.cancelled)
            if self.reader.status == .reading {
                self.reader.cancelReading()
            }
            self.completeAllInputs()
            if self.didBeginFinishing {
                self.writer.cancelWriting()
                try? FileManager.default.removeItem(at: self.outputURL)
                if let completionHandler = self.completionHandler {
                    self.dispatchCallback(with: SessionError.cancelled, completionHandler)
                }
            } else {
                self.finishIfPossible()
            }
        }
    }

    private func pumpVideo(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard status == .exporting,
              cancelled == false,
              didBeginFinishing == false,
              videoCompleted == false,
              videoProcessingInFlight == false else { return }

        if let pendingProcessedVideoFrame {
            guard input.isReadyForMoreMediaData else {
                configuration.performanceAccumulator.recordProcessedFrameWriterBackpressure()
                return
            }
            guard let adaptor = videoPixelBufferAdaptor,
                  adaptor.append(
                    pendingProcessedVideoFrame.pixelBuffer,
                    withPresentationTime: pendingProcessedVideoFrame.presentationTime
                  ) else {
                failExport(writer.error ?? SessionError.invalidStatus)
                return
            }
            self.pendingProcessedVideoFrame = nil
            processedVideoFrameCount += 1
            configuration.performanceAccumulator.recordPendingProcessedFrameWritten()
            configuration.performanceAccumulator.recordVideoSampleWritten()
        }

        var sampleCount = 0
        while input.isReadyForMoreMediaData && sampleCount < Self.maximumSamplesPerPump {
            guard status == .exporting, cancelled == false, didBeginFinishing == false else { return }
            guard reader.status == .reading, writer.status == .writing else {
                handleInactiveReaderWriter()
                return
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: 1) }
                finishTrack(.video, input: input)
                return
            }

            configuration.performanceAccumulator.recordVideoSampleRead()
            dispatchProgress(for: sampleBuffer, mediaType: .video)
            sampleCount += 1
            if configuration.videoProcessors.isEmpty || videoPixelBufferAdaptor == nil {
                guard input.append(sampleBuffer) else {
                    failExport(writer.error ?? SessionError.invalidStatus)
                    return
                }
                configuration.performanceAccumulator.recordVideoSampleWritten()
                continue
            }

            guard let frame = makeVideoFrame(from: sampleBuffer) else {
                failExport(SessionError.processedVideoFrameUnavailable)
                return
            }
            videoProcessingInFlight = true
            videoProcessingGeneration &+= 1
            let processingGeneration = videoProcessingGeneration
            let submittedAt = configuration.performanceAccumulator.now()
            configuration.performanceAccumulator.recordProcessorSubmitted()
            scheduleVideoProcessingTimeout(for: processingGeneration)
            processVideoFrame(frame, submittedAt: submittedAt) { [weak self] result, timing in
                self?.queue.async { [weak self] in
                    self?.handleProcessedVideoFrame(
                        result,
                        timing: timing,
                        generation: processingGeneration,
                        sourceSampleBuffer: sampleBuffer,
                        input: input
                    )
                }
            }
            return
        }
        if sampleCount == Self.maximumSamplesPerPump {
            queue.async { [weak self, weak input] in
                guard let self, let input, let output = self.videoOutput else { return }
                self.pumpVideo(from: output, to: input)
            }
        }
    }

    private func pumpAudio(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard status == .exporting,
              cancelled == false,
              didBeginFinishing == false,
              audioCompleted == false else { return }

        var sampleCount = 0
        while input.isReadyForMoreMediaData && sampleCount < Self.maximumSamplesPerPump {
            guard status == .exporting, cancelled == false, didBeginFinishing == false else { return }
            guard reader.status == .reading, writer.status == .writing else {
                handleInactiveReaderWriter()
                return
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: 1) }
                finishTrack(.audio, input: input)
                return
            }

            configuration.performanceAccumulator.recordAudioSampleRead()
            dispatchProgress(for: sampleBuffer, mediaType: .audio)
            sampleCount += 1
            guard input.append(sampleBuffer) else {
                failExport(writer.error ?? SessionError.invalidStatus)
                return
            }
            configuration.performanceAccumulator.recordAudioSampleWritten()
        }
        if sampleCount == Self.maximumSamplesPerPump {
            queue.async { [weak self, weak input] in
                guard let self, let input, let output = self.audioOutput else { return }
                self.pumpAudio(from: output, to: input)
            }
        }
    }

    private enum TrackKind {
        case video
        case audio
    }

    private func finishTrack(_ track: TrackKind, input: AVAssetWriterInput) {
        input.markAsFinished()
        switch track {
        case .video:
            videoCompleted = true
        case .audio:
            audioCompleted = true
        }
        finishIfPossible()
    }

    private func completeAllInputs() {
        if videoCompleted == false {
            videoInput?.markAsFinished()
            videoCompleted = true
        }
        if audioCompleted == false {
            audioInput?.markAsFinished()
            audioCompleted = true
        }
    }

    private func failExport(_ error: Error) {
        guard didBeginFinishing == false else { return }
        videoProcessingInFlight = false
        cancelVideoProcessingTimeout()
        processorError = error
        if reader.status == .reading {
            reader.cancelReading()
        }
        completeAllInputs()
        finishIfPossible()
    }

    private func handleInactiveReaderWriter() {
        if cancelled || reader.status == .cancelled || writer.status == .cancelled {
            completeAllInputs()
            finishIfPossible()
            return
        }
        failExport(reader.error ?? writer.error ?? SessionError.invalidStatus)
    }

    private func finishIfPossible() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard videoCompleted, audioCompleted, didBeginFinishing == false, let completionHandler else { return }
        didBeginFinishing = true
        cancelVideoProcessingTimeout()
        configuration.performanceAccumulator.markFinishing()
        finish(completionHandler: completionHandler)
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

        if videoPixelBufferAdaptor != nil, processedVideoFrameCount == 0 {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            dispatchCallback(with: SessionError.noProcessedVideoFrames, completionHandler)
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
                    guard self.didDeliverCallback == false else { return }
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

    private func makeVideoFrame(from sampleBuffer: CMSampleBuffer) -> MediaFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let metadata = FrameMetadata(
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer).isValid ? CMSampleBufferGetDuration(sampleBuffer) : nil,
            sourceTime: CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer),
            format: FrameFormat(pixelBuffer: pixelBuffer)
        )
        return SampleBufferFrame(sampleBuffer: sampleBuffer, metadata: metadata)
    }

    private func handleProcessedVideoFrame(
        _ result: Result<MediaFrame, Error>,
        timing: VideoProcessingTiming,
        generation: UInt64,
        sourceSampleBuffer: CMSampleBuffer,
        input: AVAssetWriterInput
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard videoProcessingInFlight, generation == videoProcessingGeneration else { return }
        cancelVideoProcessingTimeout()
        videoProcessingInFlight = false
        let ownerDeliveredAt = configuration.performanceAccumulator.now()
        configuration.performanceAccumulator.recordProcessorCompleted(
            submittedAt: timing.submittedAt,
            queueDelayNanoseconds: timing.queueDelayNanoseconds,
            executionDurationNanoseconds: timing.executionDurationNanoseconds,
            callbackCompletedAt: timing.callbackCompletedAt,
            ownerDeliveredAt: ownerDeliveredAt
        )
        guard videoCompleted == false, cancelled == false, didBeginFinishing == false else { return }

        switch result {
        case .failure(let error):
            failExport(error)
        case .success(let processedFrame):
            guard videoPixelBufferAdaptor != nil else {
                failExport(SessionError.processedVideoAdaptorUnavailable)
                return
            }
            let processedBox = UnsafeSendableBox(value: processedFrame)
            let sampleBufferBox2 = UnsafeSendableBox(value: sourceSampleBuffer)
            guard let processedPixelBuffer = extractPixelBuffer(processedBox.value) ?? CMSampleBufferGetImageBuffer(extractSampleBuffer(processedBox.value) ?? sampleBufferBox2.value) else {
                failExport(SessionError.processedVideoFrameUnavailable)
                return
            }
            let presentationTime = processedFrame.metadata.presentationTime
            pendingProcessedVideoFrame = PendingProcessedVideoFrame(
                pixelBuffer: processedPixelBuffer,
                presentationTime: presentationTime
            )
            configuration.performanceAccumulator.recordPendingProcessedFrame(at: ownerDeliveredAt)
            if status == .exporting, let videoOutput {
                pumpVideo(from: videoOutput, to: input)
            }
        }
    }

    private func scheduleVideoProcessingTimeout(for generation: UInt64) {
        guard let timeout = configuration.videoFrameProcessingTimeout,
              timeout.isFinite,
              timeout > 0 else { return }
        cancelVideoProcessingTimeout()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            // pause 只停止继续取帧；已经交给外部 processor 的调用仍受同一截止时间约束，
            // 避免卡死调用借暂停进入无界等待。
            guard let self,
                  self.videoProcessingInFlight,
                  self.videoProcessingGeneration == generation,
                  self.cancelled == false,
                  self.didBeginFinishing == false else { return }
            self.cancelVideoProcessingTimeout()
            self.videoProcessingInFlight = false
            self.cancelVideoProcessingOperation()
            self.configuration.performanceAccumulator.recordProcessorTimedOut()
            self.failExport(SessionError.videoFrameProcessingTimedOut(seconds: timeout))
        }
        videoProcessingTimeoutTimer = timer
        timer.resume()
    }

    private func cancelVideoProcessingTimeout() {
        dispatchPrecondition(condition: .onQueue(queue))
        videoProcessingTimeoutTimer?.cancel()
        videoProcessingTimeoutTimer = nil
    }

    private func processVideoFrame(
        _ frame: MediaFrame,
        submittedAt: UInt64,
        at index: Int = 0,
        accumulatedQueueDelayNanoseconds: UInt64 = 0,
        accumulatedExecutionDurationNanoseconds: UInt64 = 0,
        completion: @escaping (Result<MediaFrame, Error>, VideoProcessingTiming) -> Void
    ) {
        guard index < configuration.videoProcessors.count else {
            let completedAt = configuration.performanceAccumulator.now()
            completion(.success(frame), VideoProcessingTiming(
                submittedAt: submittedAt,
                queueDelayNanoseconds: accumulatedQueueDelayNanoseconds,
                executionDurationNanoseconds: accumulatedExecutionDurationNanoseconds,
                callbackCompletedAt: completedAt
            ))
            return
        }

        let processor = configuration.videoProcessors[index]
        let operationToken = beginVideoProcessingOperation()
        let frameBox = UnsafeSendableBox(value: frame)
        let completionBox = UnsafeSendableBox(value: completion)
        let stageSubmittedAt = configuration.performanceAccumulator.now()
        processorQueue.async { [weak self] in
            guard let self else {
                let completedAt = DispatchTime.now().uptimeNanoseconds
                completionBox.value(.failure(SessionError.invalidStatus), VideoProcessingTiming(
                    submittedAt: submittedAt,
                    queueDelayNanoseconds: accumulatedQueueDelayNanoseconds,
                    executionDurationNanoseconds: accumulatedExecutionDurationNanoseconds,
                    callbackCompletedAt: completedAt
                ))
                return
            }
            let stageStartedAt = self.configuration.performanceAccumulator.now()
            let operation = processFrame(using: processor, frame: frameBox.value) { [weak self] result in
                guard let self else {
                    let completedAt = DispatchTime.now().uptimeNanoseconds
                    completionBox.value(.failure(SessionError.invalidStatus), VideoProcessingTiming(
                        submittedAt: submittedAt,
                        queueDelayNanoseconds: accumulatedQueueDelayNanoseconds,
                        executionDurationNanoseconds: accumulatedExecutionDurationNanoseconds,
                        callbackCompletedAt: completedAt
                    ))
                    return
                }
                self.clearVideoProcessingOperation(token: operationToken)
                let stageCompletedAt = self.configuration.performanceAccumulator.now()
                let queueDelayNanoseconds = Self.addingClamped(
                    accumulatedQueueDelayNanoseconds,
                    Self.elapsedNanoseconds(from: stageSubmittedAt, to: stageStartedAt)
                )
                let executionDurationNanoseconds = Self.addingClamped(
                    accumulatedExecutionDurationNanoseconds,
                    Self.elapsedNanoseconds(from: stageStartedAt, to: stageCompletedAt)
                )
                switch result {
                case .success(let processedFrame):
                    self.processVideoFrame(
                        processedFrame,
                        submittedAt: submittedAt,
                        at: index + 1,
                        accumulatedQueueDelayNanoseconds: queueDelayNanoseconds,
                        accumulatedExecutionDurationNanoseconds: executionDurationNanoseconds,
                        completion: completionBox.value
                    )
                case .failure(let error):
                    completionBox.value(.failure(error), VideoProcessingTiming(
                        submittedAt: submittedAt,
                        queueDelayNanoseconds: queueDelayNanoseconds,
                        executionDurationNanoseconds: executionDurationNanoseconds,
                        callbackCompletedAt: stageCompletedAt
                    ))
                }
            }
            self.installVideoProcessingOperation(operation, token: operationToken)
        }
    }

    private func beginVideoProcessingOperation() -> UInt64 {
        videoProcessingOperationLock.lock()
        videoProcessingOperationToken &+= 1
        let token = videoProcessingOperationToken
        videoProcessingOperation = nil
        videoProcessingOperationLock.unlock()
        return token
    }

    private func installVideoProcessingOperation(_ operation: FrameProcessingOperation?, token: UInt64) {
        videoProcessingOperationLock.lock()
        if videoProcessingOperationToken == token {
            videoProcessingOperation = operation
            videoProcessingOperationLock.unlock()
        } else {
            videoProcessingOperationLock.unlock()
            operation?.cancel()
        }
    }

    private func clearVideoProcessingOperation(token: UInt64) {
        videoProcessingOperationLock.lock()
        if videoProcessingOperationToken == token {
            videoProcessingOperation = nil
        }
        videoProcessingOperationLock.unlock()
    }

    private func cancelVideoProcessingOperation() {
        videoProcessingOperationLock.lock()
        videoProcessingOperationToken &+= 1
        let operation = videoProcessingOperation
        videoProcessingOperation = nil
        videoProcessingOperationLock.unlock()
        operation?.cancel()
    }

    private static func elapsedNanoseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }

    private static func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let addition = lhs.addingReportingOverflow(rhs)
        return addition.overflow ? .max : addition.partialValue
    }

    private func dispatchProgress(for sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        let fraction = (CMSampleBufferGetPresentationTimeStamp(sampleBuffer) - configuration.timeRange.start).seconds / max(duration.seconds, 0.001)
        switch mediaType {
        case .video:
            dispatchProgressCallback { $0.updateVideoEncodingProgress(fractionCompleted: fraction) }
        case .audio:
            dispatchProgressCallback { $0.updateAudioEncodingProgress(fractionCompleted: fraction) }
        default:
            break
        }
    }

    private func dispatchProgressCallback(with updater: @escaping (ExportProgress) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let progress else { return }
        updater(progress)
        pendingProgressSnapshot = progress.makeSnapshot()
        guard progressHandler != nil, progressDeliveryTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.progressDeliveryInterval)
        timer.setEventHandler { [weak self] in
            self?.flushProgressCallback()
        }
        progressDeliveryTimer = timer
        timer.resume()
    }

    private func flushProgressCallback() {
        dispatchPrecondition(condition: .onQueue(queue))
        progressDeliveryTimer?.cancel()
        progressDeliveryTimer = nil
        guard let snapshot = pendingProgressSnapshot,
              let progressHandler else {
            pendingProgressSnapshot = nil
            return
        }
        pendingProgressSnapshot = nil
        let snapshotBox = UnsafeSendableBox(value: snapshot)
        let handlerBox = UnsafeSendableBox(value: progressHandler)
        DispatchQueue.main.async {
            handlerBox.value(snapshotBox.value)
        }
    }

    private func dispatchStatus(_ status: Status) {
        let box = UnsafeSendableBox(value: statusHandler)
        DispatchQueue.main.async {
            box.value?(status)
        }
    }

    private func dispatchCallback(with error: Error?, _ completionHandler: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard didDeliverCallback == false else { return }
        didDeliverCallback = true
        cancelVideoProcessingTimeout()
        configuration.performanceAccumulator.markFinal()
        flushProgressCallback()
        let finalStatus: Status = error == nil ? .completed : (cancelled ? .cancelled : .failed)
        let shouldDispatchStatus = status != finalStatus
        status = finalStatus
        progressHandler = nil
        pendingProgressSnapshot = nil
        self.completionHandler = nil
        lifecycleRetain = nil
        let completionBox = UnsafeSendableBox(value: completionHandler)
        let statusBox = UnsafeSendableBox(value: statusHandler)
        DispatchQueue.main.async {
            if shouldDispatchStatus {
                statusBox.value?(finalStatus)
            }
            completionBox.value(error)
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

#if DEBUG
extension VideoAssetExportSession {
    var _usesImplicitVideoCompositionForTesting: Bool {
        videoOutput is AVAssetReaderVideoCompositionOutput
    }
}
#endif
