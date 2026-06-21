//
//  VideoX.swift
//  KakaposExamples
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

public typealias ExportComplete = (Result<URL, VideoX.Error>) -> Void

@available(*, deprecated, message: "Typo. Use `VideoX` instead", renamed: "VideoX")
public typealias Exporter = VideoX

public struct VideoX {
    let provider: VideoX.Provider
    
    /// Craate exporter.
    /// - Parameter provider: Configure export information.
    public init(provider: VideoX.Provider) {
        self.provider = provider
    }

    public final class ExportTask {
        public enum Status: Equatable {
            case idle
            case exporting
            case paused
            case completed
            case cancelled
            case failed
        }

        public let assetExportSession: AVAssetExportSession?
        public let readerWriterJob: ReaderWriterExportJob?

        public var supportsPauseResume: Bool {
            readerWriterJob != nil
        }

        public var progressInfo: ReaderWriterExportJob.ProgressInfo? {
            readerWriterJob?.lastProgressInfo
        }

        public var summaryText: String {
            if let readerWriterJob {
                return readerWriterJob.summary.summaryText
            }
            guard assetExportSession != nil else {
                return "state idle · pipeline unavailable"
            }
            return "state \(status) · assetExportSession"
        }

        public var status: Status {
            if let readerWriterJob {
                return Self.status(for: readerWriterJob.status)
            }
            guard let assetExportSession else {
                return .idle
            }
            return Self.status(for: assetExportSession.status)
        }

        init(assetExportSession: AVAssetExportSession) {
            self.assetExportSession = assetExportSession
            self.readerWriterJob = nil
        }

        init(readerWriterJob: ReaderWriterExportJob) {
            self.assetExportSession = nil
            self.readerWriterJob = readerWriterJob
        }

        public func start(
            complete: @escaping ExportComplete,
            progress: ((Float) -> Void)? = nil,
            progressInfo: ((ReaderWriterExportJob.ProgressInfo) -> Void)? = nil
        ) {
            if let readerWriterJob {
                readerWriterJob.progressHandler = { info in
                    progress?(Float(info.overallFractionCompleted))
                    progressInfo?(info)
                }
                readerWriterJob.export { result in
                    switch result {
                    case .success(let outputURL):
                        progress?(1.0)
                        complete(.success(outputURL))
                    case .failure(let error):
                        if case VideoX.Error.exportCancelled = VideoX.Error.toError(error) {
                            progress?(0.0)
                        }
                        complete(.failure(VideoX.Error.toError(error)))
                    }
                }
                return
            }

            guard let assetExportSession else {
                progress?(0.0)
                complete(.failure(VideoX.Error.exportSessionEmpty))
                return
            }
            if let progress {
                let progressObserver = ExportSessionProgressObserver(
                    session: assetExportSession,
                    keyPath: \.progress,
                    handler: progress
                )
                progressObserver.start()
                assetExportSession.exportAsynchronously(completionHandler: { [weak assetExportSession] in
                    progressObserver.stop()
                    guard let session = assetExportSession else {
                        complete(.failure(VideoX.Error.exportSessionEmpty))
                        return
                    }
                    switch session.status {
                    case .completed:
                        progress(1.0)
                        if let outputURL = session.outputURL {
                            complete(.success(outputURL))
                        } else {
                            complete(.failure(VideoX.Error.exportOutputURL))
                        }
                    case .cancelled:
                        complete(.failure(VideoX.Error.exportCancelled))
                    case .failed:
                        complete(.failure(VideoX.Error.toError(session.error)))
                    default:
                        complete(.failure(VideoX.Error.exportAsynchronously(session.status)))
                    }
                })
            } else {
                assetExportSession.exportAsynchronously(completionHandler: { [weak assetExportSession] in
                    guard let session = assetExportSession else {
                        complete(.failure(VideoX.Error.exportSessionEmpty))
                        return
                    }
                    switch session.status {
                    case .completed:
                        if let outputURL = session.outputURL {
                            complete(.success(outputURL))
                        } else {
                            complete(.failure(VideoX.Error.exportOutputURL))
                        }
                    case .cancelled:
                        complete(.failure(VideoX.Error.exportCancelled))
                    case .failed:
                        complete(.failure(VideoX.Error.toError(session.error)))
                    default:
                        complete(.failure(VideoX.Error.exportAsynchronously(session.status)))
                    }
                })
            }
        }

        public func pause() {
            readerWriterJob?.pause()
        }

        public func resume() {
            readerWriterJob?.resume()
        }

        public func cancel() {
            if let readerWriterJob {
                readerWriterJob.cancel()
            } else {
                assetExportSession?.cancelExport()
            }
        }

        private static func status(for status: AVAssetExportSession.Status) -> Status {
            switch status {
            case .unknown:
                return .idle
            case .waiting, .exporting:
                return .exporting
            case .completed:
                return .completed
            case .failed:
                return .failed
            case .cancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        }

        private static func status(for status: ReaderWriterExportJob.Status) -> Status {
            switch status {
            case .idle:
                return .idle
            case .exporting:
                return .exporting
            case .paused:
                return .paused
            case .completed:
                return .completed
            case .cancelled:
                return .cancelled
            case .failed:
                return .failed
            }
        }
    }
    
    public func makeAssetExportSession(options: [VideoX.Option: Any] = [:], instructions: [CompositionInstruction]) throws -> AVAssetExportSession {
        guard let exportSession = try create(AVAssetExportSession.self, options: options, instructions: instructions) else {
            throw VideoX.Error.exportSessionEmpty
        }
        return exportSession
    }

    /// Build a controllable export job when the configured pipeline is `.readerWriter`.
    /// Returns `nil` for the legacy `AVAssetExportSession` route.
    public func makeExportJob(
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> ReaderWriterExportJob? {
        guard VideoX.Option.setupExportPipeline(options: options) == .readerWriter else {
            return nil
        }
        return try makeReaderWriterExportJob(options: options, instructions: instructions)
    }

    public func makeExportTask(
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> ExportTask {
        if let exportJob = try makeExportJob(options: options, instructions: instructions) {
            return ExportTask(readerWriterJob: exportJob)
        }
        return ExportTask(assetExportSession: try makeAssetExportSession(options: options, instructions: instructions))
    }

    /// Build a reader/writer export job directly.
    /// Use this when you need explicit pause, resume, cancel, and status control.
    public func makeReaderWriterExportJob(
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction]
    ) throws -> ReaderWriterExportJob {
        try buildReaderWriterExportJob(options: options, instructions: instructions)
    }
    
    /// Export the video.
    /// - Parameters:
    ///   - options: Setup other parameters about export video.
    ///   - instructions: Operation procedure.
    ///   - complete: The conversion is complete, including success or failure.
    ///   - progress: Specifies the progress of the export on a scale from 0 to 1.0.
    public func export(
        options: [VideoX.Option: Any] = [:],
        instructions: [CompositionInstruction],
        complete: @escaping ExportComplete,
        progress: ((Float) -> Void)? = nil
    ) -> AVAssetExportSession? {
        do {
            let exportTask = try makeExportTask(options: options, instructions: instructions)
            exportTask.start(complete: complete, progress: progress)
            return exportTask.assetExportSession
        } catch {
            progress?(0.0)
            complete(.failure(VideoX.Error.toError(error)))
        }
        return nil
    }
    
    /// Export the video after add the filter.
    /// - Parameters:
    ///   - options: Setup other parameters about export video.
    ///   - filtering: Filters work to filter pixel buffer.
    ///   - complete: The conversion is complete, including success or failure.
    ///   - progress: Specifies the progress of the export on a scale from 0 to 1.0.
    public func export(options: [VideoX.Option: Any] = [:],
                       filtering: @escaping (CVPixelBuffer, @escaping BufferBlock) -> Void,
                       complete: @escaping ExportComplete,
                       progress: ((Float) -> Void)? = nil) {
        let instruction = FilterInstruction(filtering: filtering)
        let _ = export(options: options, instructions: [instruction], complete: complete, progress: progress)
    }
}

extension VideoX {

    private struct ExportComponents {
        let composition: AVMutableComposition
        let videoComposition: AVVideoComposition?
        let audioMix: AVAudioMix?
        let exportTimeRange: CMTimeRange
    }
    
    private func create<R>(_ type: R.Type, options: [VideoX.Option: Any], instructions: [CompositionInstruction]) throws -> R? {
        let components = try buildExportComponents(options: options, instructions: instructions)
        
        if type == AVAssetExportSession.self {
            guard let avFileType = self.provider.fileType?.avFileType else {
                throw VideoX.Error.unsupportedFileType
            }
            let presetName = VideoX.Option.setupPresetName(options: options)
            guard let exportSession = AVAssetExportSession(asset: components.composition, presetName: presetName) else {
                throw VideoX.Error.exportSessionEmpty
            }
            exportSession.outputURL = self.provider.outputURL
            exportSession.outputFileType = avFileType
            exportSession.shouldOptimizeForNetworkUse = VideoX.Option.setupOptimizeForNetworkUse(options: options)
            exportSession.timeRange = components.exportTimeRange
            if let audioMix = components.audioMix {
                exportSession.audioMix = audioMix
            }
            exportSession.videoComposition = components.videoComposition
            return exportSession as? R
        } else if type == AVPlayerItem.self {
            let playerItem = AVPlayerItem(asset: components.composition)
            playerItem.videoComposition = components.videoComposition
            if let audioMix = components.audioMix {
                playerItem.audioMix = audioMix
            }
            return playerItem as? R
        } else if type == AVAssetImageGenerator.self {
            let imageGenerator = AVAssetImageGenerator(asset: components.composition)
            imageGenerator.videoComposition = components.videoComposition
            return imageGenerator as? R
        }
        return nil
    }

    private func buildExportComponents(options: [VideoX.Option: Any], instructions: [CompositionInstruction]) throws -> ExportComponents {
        guard let videoTrack = self.provider.videoTracks.first else {
            throw VideoX.Error.videoTrackEmpty
        }
        let composition = try setupComposition(options: options)
        let track = try setupVideoTrack(videoTrack: videoTrack, composition: composition)
        let exportTimeRange = VideoX.Option.setupExportSessionTimeRange(duration: provider.duration, options: options)

        let videoComposition: AVVideoComposition?
        if instructions.isEmpty {
            videoComposition = nil
        } else {
            let compositeInstruction = CompositeInstruction(instructions: instructions)
            compositeInstruction.timeRange = exportTimeRange
            compositeInstruction.initCompositionTrack(track, provider: provider, options: options)
            videoComposition = setupVideoComposition(options: options, composition: composition, instructions: [compositeInstruction])
        }
        let audioMix = setupAudioMix()
        return ExportComponents(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            exportTimeRange: exportTimeRange
        )
    }

    private func buildReaderWriterExportJob(options: [VideoX.Option: Any], instructions: [CompositionInstruction]) throws -> ReaderWriterExportJob {
        guard let avFileType = self.provider.fileType?.avFileType else {
            throw VideoX.Error.unsupportedFileType
        }
        let instructionPlan = extractReaderWriterInstructionPlan(from: instructions)
        let components = try buildExportComponents(options: options, instructions: instructionPlan.compositionInstructions)
        return ReaderWriterExportJob(
            asset: components.composition,
            outputURL: self.provider.outputURL,
            fileType: avFileType,
            timeRange: components.exportTimeRange,
            videoComposition: components.videoComposition,
            audioMix: components.audioMix,
            videoProcessors: instructionPlan.videoProcessors,
            shouldOptimizeForNetworkUse: VideoX.Option.setupOptimizeForNetworkUse(options: options)
        )
    }
    
    private func setupComposition(options: [VideoX.Option: Any]) throws -> AVMutableComposition {
        let naturalSize = VideoX.Option.setupVideoRenderSize(provider.videoTracks, asset: provider.asset, options: options)
        let composition = AVMutableComposition()
        composition.naturalSize = naturalSize
        return composition
    }
    
    private func setupVideoTrack(videoTrack: AVAssetTrack, composition: AVMutableComposition) throws -> AVCompositionTrack {
        guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoX.Error.addVideoTrack
        }
        videoCompositionTrack.preferredTransform = videoTrack.preferredTransform
        let timeRange = CMTimeRangeMake(start: .zero, duration: provider.duration)
        try videoCompositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        
        if let audio = self.provider.audioTracks.first {
            let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audio, at: .zero)
        }
        
        return videoCompositionTrack
    }
    
    private func setupVideoComposition(options: [VideoX.Option: Any], composition: AVComposition, instructions: [CompositionInstruction]) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        videoComposition.frameDuration = VideoX.Option.setupVideoFrameDuration(options: options)
        if #available(macOS 10.14, *) {
            videoComposition.renderScale = VideoX.Option.setupRenderScale(options: options)
        }
        videoComposition.renderSize = setupRenderSize(for: composition, instructions: instructions)
        videoComposition.instructions = instructions
        return videoComposition
    }
    
    private func setupRenderSize(for composition: AVComposition, instructions: [CompositionInstruction]) -> CGSize {
        var renderSize = composition.naturalSize
        
        for instruction in instructions {
            if let compositeInstruction = instruction as? CompositeInstruction {
                for subInstruction in compositeInstruction.instructions {
                    if let rotateInstruction = subInstruction as? RotateInstruction {
                        renderSize = rotateInstruction.rotatedSize(from: renderSize)
                        break
                    }
                }
            } else if let rotateInstruction = instruction as? RotateInstruction {
                renderSize = rotateInstruction.rotatedSize(from: renderSize)
                break
            }
        }
        
        return renderSize
    }
    
    private func setupAudioMix() -> AVAudioMix? {
        let inputParameters: [AVMutableAudioMixInputParameters] = []
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        return audioMix
    }

    private func extractReaderWriterInstructionPlan(from instructions: [CompositionInstruction]) -> (compositionInstructions: [CompositionInstruction], videoProcessors: [FrameProcessor]) {
        var compositionInstructions: [CompositionInstruction] = []
        var videoProcessors: [FrameProcessor] = []

        for instruction in instructions {
            if let processorInstruction = instruction as? FrameProcessorProvidingInstruction,
               let processor = processorInstruction.kakaposFrameProcessor {
                videoProcessors.append(processor)
            } else {
                compositionInstructions.append(instruction)
            }
        }

        return (compositionInstructions, videoProcessors)
    }
}

final class ExportSessionProgressObserver<Session: NSObject> {
    private weak var session: Session?
    private let handler: (Float) -> Void
    private let keyPath: KeyPath<Session, Float>
    private var observation: NSKeyValueObservation?

    init(session: Session, keyPath: KeyPath<Session, Float>, handler: @escaping (Float) -> Void) {
        self.session = session
        self.keyPath = keyPath
        self.handler = handler
    }

    func start() {
        handler(0.0)
        observation = session?.observe(keyPath, options: [.new]) { [weak self] session, _ in
            guard let self else { return }
            let progress = min(max(session[keyPath: self.keyPath], 0), 1)
            DispatchQueue.main.async {
                self.handler(progress)
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }
}
