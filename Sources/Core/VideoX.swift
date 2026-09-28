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
            let exportSession = try makeAssetExportSession(options: options, instructions: instructions)
            exportSession.exportAsynchronously(completionHandler: { [weak exportSession] in
                guard let session = exportSession else {
                    complete(.failure(VideoX.Error.exportSessionEmpty))
                    return
                }
                progress?(session.progress)
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
    private func create<R>(_ type: R.Type, options: [VideoX.Option: Any], instructions: [CompositionInstruction]) throws -> R? {
        let composition = try setupComposition(options: options)
        let videoCompositionTrack = try setupVideoTrack(composition: composition)
        let timeRange = CMTimeRangeMake(start: .zero, duration: provider.duration)
        let instructions = instructions.map {
            $0.initCompositionTrack(videoCompositionTrack, provider: provider, options: options)
            $0.timeRange = timeRange
            return $0
        }
        let videoComposition = try setupVideoComposition(options: options, composition: composition)
        videoComposition.instructions = instructions
        
        if type == AVAssetExportSession.self {
            guard let avFileType = self.provider.fileType?.avFileType else {
                throw VideoX.Error.unsupportedFileType
            }
            let presetName = VideoX.Option.setupPresetName(options: options)
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
                throw VideoX.Error.exportSessionEmpty
            }
            exportSession.outputURL = self.provider.outputURL
            exportSession.outputFileType = avFileType
            exportSession.shouldOptimizeForNetworkUse = VideoX.Option.setupOptimizeForNetworkUse(options: options)
            if let range = VideoX.Option.setupExportSessionTimeRange(duration: self.provider.duration, options: options) {
                exportSession.timeRange = range
            }
            if let audioMix = setupAudioMix() {
                exportSession.audioMix = audioMix
            }
            exportSession.videoComposition = videoComposition
            return exportSession as? R
        } else if type == AVPlayerItem.self {
            let playerItem = AVPlayerItem(asset: composition)
            playerItem.videoComposition = videoComposition
            if let audioMix = setupAudioMix() {
                playerItem.audioMix = audioMix
            }
            return playerItem as? R
        } else if type == AVAssetImageGenerator.self {
            let imageGenerator = AVAssetImageGenerator(asset: composition)
            imageGenerator.videoComposition = videoComposition
            return imageGenerator as? R
        }
        return nil
    }
    
    private func setupComposition(options: [VideoX.Option: Any]) throws -> AVMutableComposition {
        let naturalSize = VideoX.Option.setupVideoRenderSize(provider.videoTracks, asset: provider.asset, options: options)
        let composition = AVMutableComposition()
        composition.naturalSize = naturalSize
        return composition
    }
    
    private func setupVideoTrack(composition: AVMutableComposition) throws -> AVCompositionTrack {
        guard let track = self.provider.videoTracks.first else {
            throw VideoX.Error.videoTrackEmpty
        }
        guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoX.Error.addVideoTrack
        }
        let timeRange = CMTimeRangeMake(start: .zero, duration: provider.duration)
        try videoCompositionTrack.insertTimeRange(timeRange, of: track, at: .zero)
        
        if let audio = self.provider.audioTracks.first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioCompositionTrack.insertTimeRange(timeRange, of: audio, at: .zero)
        }
        
        return videoCompositionTrack
    }
    
    private func setupVideoComposition(options: [VideoX.Option: Any], composition: AVComposition) throws -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition(propertiesOf: provider.asset)
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        videoComposition.frameDuration = VideoX.Option.setupVideoFrameDuration(options: options)
        videoComposition.renderSize = composition.naturalSize
        //videoComposition.animationTool = setupAnimationTool(renderSize: composition.naturalSize)
        if #available(macOS 10.14, iOS 10, tvOS 9.0, *) {
            videoComposition.renderScale = VideoX.Option.setupRenderScale(options: options)
        }
        return videoComposition
    }
    
    private func setupAnimationTool(renderSize: CGSize) -> AVVideoCompositionCoreAnimationTool? {
        let parentLayer = CALayer()
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: CGPoint.zero, size: renderSize)
        videoLayer.frame = CGRect(origin: CGPoint.zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        //parentLayer.addSublayer(animationLayer)
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }
    
    private func  setupAudioMix() -> AVAudioMix? {
        let inputParameters: [AVMutableAudioMixInputParameters] = []
        
        // Create audioMix. Specify inputParameters.
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        return audioMix
    }
}
