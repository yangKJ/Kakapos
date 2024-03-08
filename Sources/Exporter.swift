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
public typealias PixelBufferCallback = (_ buffer: ExporterBuffer, _ block: @escaping (ExporterBuffer) -> Void) -> Void?
public typealias ExportComplete = (Result<URL, Exporter.Error>) -> Void

public struct Exporter {
    
    let provider: Exporter.Provider
    
    /// Craate exporter.
    /// - Parameter provider: Configure export information.
    public init(provider: Exporter.Provider) {
        self.provider = provider
    }
    
    /// Export the video after add the filter.
    /// - Parameters:
    ///   - options: Setup other parameters about export video.
    ///   - filtering: Filters work to filter pixel buffer.
    ///   - complete: The conversion is complete, including success or failure.
    ///   - progress: Specifies the progress of the export on a scale from 0 to 1.0.
    public func export(options: [Exporter.Option: Any] = [:],
                       filtering: @escaping PixelBufferCallback,
                       complete: @escaping ExportComplete,
                       progress: ((Float) -> Void)? = nil) {
        do {
            let (composition, videoComposition) = try setupComposition(options: options, filtering: filtering)
            let exportSession = try setupExportSession(composition: composition, options: options)
            exportSession.videoComposition = videoComposition
            exportSession.exportAsynchronously(completionHandler: {
                progress?(exportSession.progress)
                switch exportSession.status {
                case .completed:
                    progress?(1.0)
                    complete(.success(provider.outputURL))
                case .cancelled:
                    progress?(exportSession.progress)
                    complete(.failure(Exporter.Error.exportCancelled))
                case .failed:
                    progress?(exportSession.progress)
                    complete(.failure(Exporter.Error.toError(exportSession.error)))
                default:
                    progress?(exportSession.progress)
                    complete(.failure(Exporter.Error.exportAsynchronously(exportSession.status)))
                    break
                }
            })
        } catch {
            progress?(0.0)
            complete(.failure(Exporter.Error.toError(error)))
        }
    }
}

extension Exporter {
    
    private func setupExportSession(composition: AVComposition, options: [Exporter.Option: Any]) throws -> AVAssetExportSession {
        guard let avFileType = provider.fileType?.avFileType else {
            throw Exporter.Error.unsupportedFileType
        }
        let presetName = Exporter.Option.setupPresetName(options: options)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw Exporter.Error.exportSessionEmpty
        }
        exportSession.outputURL = provider.outputURL
        exportSession.outputFileType = avFileType
        exportSession.shouldOptimizeForNetworkUse = Exporter.Option.setupOptimizeForNetworkUse(options: options)
        if let range = Exporter.Option.setupExportSessionTimeRange(duration: provider.asset.duration, options: options) {
            exportSession.timeRange = range
        }
        return exportSession
    }
    
    private func setupComposition(options: [Exporter.Option: Any], filtering: @escaping PixelBufferCallback) throws -> (AVComposition, AVVideoComposition) {
        var videoFrameDuration = CMTimeMake(value: 1, timescale: 30)
        for (key, value) in options {
            switch (key, value) {
            case (.VideoCompositionFrameDuration, let value as CMTime):
                videoFrameDuration = value
            default:
                break
            }
        }
        
        let asset = self.provider.asset
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw Exporter.Error.videoTrackEmpty
        }
        let naturalSize = Exporter.Option.setupVideoRenderSize(videoTracks, asset: asset, options: options)
        let composition = AVMutableComposition()
        composition.naturalSize = naturalSize
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Exporter.Error.addVideoTrack
        }
        let timeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)
        try videoTrack.insertTimeRange(timeRange, of: track, at: .zero)
        
        if let audio = asset.tracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioCompositionTrack.insertTimeRange(timeRange, of: audio, at: .zero)
        }
        
        let instruction = CompositionInstruction(videoTrack: videoTrack, bufferCallback: filtering, options: options)
        instruction.timeRange = timeRange
        
        let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        videoComposition.customVideoCompositorClass = Compositor.self
        videoComposition.frameDuration = videoFrameDuration
        videoComposition.renderSize = naturalSize
        videoComposition.instructions = [instruction]
        videoComposition.renderScale = Exporter.Option.setupRenderScale(options: options)
        
        return (composition, videoComposition)
    }
}
