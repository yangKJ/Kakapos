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
    
    public func makeAssetExportSession(options: [VideoX.Option: Any] = [:], instructions: [CompositionInstruction]) throws -> AVAssetExportSession {
        guard let exportSession = try create(AVAssetExportSession.self, options: options, instructions: instructions) else {
            throw VideoX.Error.exportSessionEmpty
        }
        return exportSession
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
            if VideoX.Option.setupExportPipeline(options: options) == .readerWriter {
                let exportJob = try makeReaderWriterExportJob(options: options, instructions: instructions)
                if let progress {
                    exportJob.progressHandler = { info in
                        progress(Float(info.fractionCompleted))
                    }
                }
                exportJob.export { result in
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
                return nil
            }

            let exportSession = try makeAssetExportSession(options: options, instructions: instructions)
            if let progress = progress {
                let progressObserver = ExportSessionProgressObserver(session: exportSession, handler: progress)
                progressObserver.start()
                exportSession.exportAsynchronously(completionHandler: { [weak exportSession] in
                    progressObserver.stop()
                    guard let session = exportSession else {
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
                        break
                    }
                })
            } else {
                exportSession.exportAsynchronously(completionHandler: { [weak exportSession] in
                    guard let session = exportSession else {
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
                        break
                    }
                })
            }
            return exportSession
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
        let videoComposition: AVVideoComposition
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

        let compositeInstruction = CompositeInstruction(instructions: instructions)
        compositeInstruction.timeRange = exportTimeRange
        compositeInstruction.initCompositionTrack(track, provider: provider, options: options)

        let videoComposition = setupVideoComposition(options: options, composition: composition, instructions: [compositeInstruction])
        let audioMix = setupAudioMix()
        return ExportComponents(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            exportTimeRange: exportTimeRange
        )
    }

    private func makeReaderWriterExportJob(options: [VideoX.Option: Any], instructions: [CompositionInstruction]) throws -> ReaderWriterExportJob {
        guard let avFileType = self.provider.fileType?.avFileType else {
            throw VideoX.Error.unsupportedFileType
        }
        let components = try buildExportComponents(options: options, instructions: instructions)
        return ReaderWriterExportJob(
            asset: components.composition,
            outputURL: self.provider.outputURL,
            fileType: avFileType,
            timeRange: components.exportTimeRange,
            videoComposition: components.videoComposition,
            audioMix: components.audioMix
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
}

private final class ExportSessionProgressObserver {
    private weak var session: AVAssetExportSession?
    private let handler: (Float) -> Void
    private let queue = DispatchQueue(label: "com.condy.kakapos.export-progress")
    private var timer: DispatchSourceTimer?

    init(session: AVAssetExportSession, handler: @escaping (Float) -> Void) {
        self.session = session
        self.handler = handler
    }

    func start() {
        handler(0.0)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, let session = self.session else { return }
            let progress = min(max(session.progress, 0), 1)
            DispatchQueue.main.async {
                self.handler(progress)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
