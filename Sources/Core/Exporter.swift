//
//  Exporter.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

public typealias ExporterBuffer = CVPixelBuffer
public typealias ExportComplete = (Result<URL, Exporter.Error>) -> Void

public struct Exporter {
    
    let provider: Exporter.Provider
    
    /// Craate exporter.
    /// - Parameter provider: Configure export information.
    public init(provider: Exporter.Provider) {
        self.provider = provider
    }
    
    /// Export the video.
    /// - Parameters:
    ///   - options: Setup other parameters about export video.
    ///   - instructions: Operation procedure.
    ///   - complete: The conversion is complete, including success or failure.
    ///   - progress: Specifies the progress of the export on a scale from 0 to 1.0.
    public func export(
        options: [Exporter.Option: Any] = [:],
        instructions: [CompositionInstruction],
        complete: @escaping ExportComplete,
        progress: ((Float) -> Void)? = nil
    ) -> AVAssetExportSession? {
        do {
            let (composition, videoComposition) = try setupComposition(options: options, instructions: instructions)
            let exportSession = try setupExportSession(composition: composition, options: options)
            exportSession.videoComposition = videoComposition
            exportSession.exportAsynchronously(completionHandler: { [weak exportSession] in
                guard let session = exportSession else {
                    complete(.failure(Exporter.Error.exportSessionEmpty))
                    return
                }
                progress?(session.progress)
                switch session.status {
                case .completed:
                    if let outputURL = session.outputURL {
                        complete(.success(outputURL))
                    } else {
                        complete(.failure(Exporter.Error.exportOutputURL))
                    }
                case .cancelled:
                    complete(.failure(Exporter.Error.exportCancelled))
                case .failed:
                    complete(.failure(Exporter.Error.toError(session.error)))
                default:
                    complete(.failure(Exporter.Error.exportAsynchronously(session.status)))
                    break
                }
            })
            return exportSession
        } catch {
            progress?(0.0)
            complete(.failure(Exporter.Error.toError(error)))
        }
        return nil
    }
    
    /// Export the video after add the filter.
    /// - Parameters:
    ///   - options: Setup other parameters about export video.
    ///   - filtering: Filters work to filter pixel buffer.
    ///   - complete: The conversion is complete, including success or failure.
    ///   - progress: Specifies the progress of the export on a scale from 0 to 1.0.
    public func export(options: [Exporter.Option: Any] = [:],
                       filtering: @escaping FilterInstruction.PixelBufferCallback,
                       complete: @escaping ExportComplete,
                       progress: ((Float) -> Void)? = nil) {
        let instruction = FilterInstruction(filtering: filtering)
        let _ = export(options: options, instructions: [instruction], complete: complete, progress: progress)
    }
}

extension Exporter {
    
    private func setupExportSession(composition: AVComposition, options: [Exporter.Option: Any]) throws -> AVAssetExportSession {
        guard let avFileType = self.provider.fileType?.avFileType else {
            throw Exporter.Error.unsupportedFileType
        }
        let presetName = Exporter.Option.setupPresetName(options: options)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw Exporter.Error.exportSessionEmpty
        }
        exportSession.outputURL = self.provider.outputURL
        exportSession.outputFileType = avFileType
        exportSession.shouldOptimizeForNetworkUse = Exporter.Option.setupOptimizeForNetworkUse(options: options)
        if let range = Exporter.Option.setupExportSessionTimeRange(duration: self.provider.duration, options: options) {
            exportSession.timeRange = range
        }
        return exportSession
    }
    
    private func setupComposition(options: [Exporter.Option: Any], instructions: [CompositionInstruction]) throws -> (AVComposition, AVVideoComposition) {
        guard let track = self.provider.videoTracks.first else {
            throw Exporter.Error.videoTrackEmpty
        }
        let naturalSize = Exporter.Option.setupVideoRenderSize(self.provider.videoTracks, asset: provider.asset, options: options)
        let composition = AVMutableComposition()
        composition.naturalSize = naturalSize
        guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Exporter.Error.addVideoTrack
        }
        let timeRange = CMTimeRangeMake(start: .zero, duration: self.provider.duration)
        try videoCompositionTrack.insertTimeRange(timeRange, of: track, at: .zero)
        
        if let audio = self.provider.audioTracks.first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioCompositionTrack.insertTimeRange(timeRange, of: audio, at: .zero)
        }
        
        let instructions = instructions.map {
            $0.initCompositionTrack(videoCompositionTrack, provider: provider, options: options)
            $0.timeRange = timeRange
            return $0
        }
        
        let videoComposition = AVMutableVideoComposition(propertiesOf: provider.asset)
        videoComposition.customVideoCompositorClass = Compositor.self
        videoComposition.frameDuration = Exporter.Option.setupVideoFrameDuration(options: options)
        videoComposition.renderSize = naturalSize
        videoComposition.instructions = instructions
        videoComposition.animationTool = Exporter.Option.setupAnimationTool(options: options)
        if #available(macOS 10.14, iOS 10, tvOS 9.0, *) {
            videoComposition.renderScale = Exporter.Option.setupRenderScale(options: options)
        }
        
        return (composition, videoComposition)
    }
}
