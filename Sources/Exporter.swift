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

public struct Exporter {
    
    public typealias PixelBufferCallback = (_ buffer: ExporterBuffer) -> ExporterBuffer?
    public typealias ExportComplete = (Result<URL, Exporter.Error>) -> Void
    
    /// Export the video after add the filter.
    /// - Parameters:
    ///   - provider: Configure export information.
    ///   - filtering: Filters work to filter pixel buffer.
    ///   - complete: The conversion is complete, including success or failure.
    public static func export(provider: ExporterProvider, filtering: @escaping PixelBufferCallback, complete: @escaping ExportComplete) {
        guard let track = provider.asset.tracks(withMediaType: .video).first else {
            complete(.failure(Exporter.Error.videoTrackEmpty))
            return
        }
        
        let composition = AVMutableComposition()
        composition.naturalSize = track.naturalSize
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            complete(.failure(Exporter.Error.addVideoTrack))
            return
        }
        
        do {
            try videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: provider.asset.duration), of: track, at: .zero)
        } catch {
            complete(.failure(Exporter.Error.error(error)))
        }
        
        var audioTrack: AVMutableCompositionTrack? = nil
        if let audio = provider.asset.tracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            audioTrack = audioCompositionTrack
            do {
                try audioTrack!.insertTimeRange(CMTimeRangeMake(start: .zero, duration: provider.asset.duration), of: audio, at: .zero)
            } catch {
                complete(.failure(Exporter.Error.error(error)))
            }
        }
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.trackID = videoTrack.trackID
        
        let instruction = CompositionInstruction(trackID: videoTrack.trackID, bufferCallback: filtering)
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: provider.asset.duration)
        instruction.layerInstructions = [layerInstruction]
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = Compositor.self
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        videoComposition.instructions = [instruction]
        
        guard let export = AVAssetExportSession(asset: composition, presetName: provider.presetName) else {
            complete(.failure(Exporter.Error.exportSessionEmpty))
            return
        }
        export.videoComposition = videoComposition
        export.outputURL = provider.outputURL
        export.outputFileType = provider.fileType.avFileType
        //export.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        export.shouldOptimizeForNetworkUse = provider.optimizeForNetworkUse
        
        export.exportAsynchronously { [weak export] in
            guard let export = export else { return }
            DispatchQueue.main.async {
                switch export.status {
                case .failed:
                    if let error = export.error {
                        complete(.failure(Exporter.Error.error(error)))
                    } else {
                        complete(.failure(Exporter.Error.unknown))
                    }
                case .completed:
                    complete(.success(provider.outputURL))
                default:
                    complete(.failure(Exporter.Error.exportAsynchronously(export.status)))
                    break
                }
            }
        }
    }
}
