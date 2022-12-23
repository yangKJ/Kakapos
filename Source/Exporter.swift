//
//  Exporter.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

public struct Exporter {
    
    public typealias PixelBufferCallback = (CVPixelBuffer) -> CVPixelBuffer
    public typealias CompletionCallback = (URL?, Error?) -> Void
    
    let asset: AVAsset
    
    public var presetName: String = AVAssetExportPresetHighestQuality {
        didSet {
            if !AVAssetExportSession.allExportPresets().contains(presetName) {
                presetName = AVAssetExportPresetMediumQuality
            }
        }
    }
    
    public init(videoURL: URL) {
        self.init(asset: AVAsset(url: videoURL))
    }
    
    public init(asset: AVAsset) {
        self.asset = asset
    }
    
    /// Export the video after injecting the filter.
    /// - Parameters:
    ///   - outputURL: Specifies the sandbox address of the exported video.
    ///   - filtering: Filters work to filter pixel buffer.
    ///   - completionHandler: The export is complete.
    public func export(outputURL: URL, filtering: @escaping PixelBufferCallback, completionHandler: @escaping CompletionCallback) {
        guard let track = self.asset.tracks(withMediaType: .video).first else {
            completionHandler(nil, nil)
            return
        }
        
        let composition = AVMutableComposition()
        composition.naturalSize = track.naturalSize
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completionHandler(nil, nil)
            return
        }
        
        do {
            try videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.asset.duration), of: track, at: .zero)
        } catch {
            completionHandler(nil, error)
        }
        
        if let audio = self.asset.tracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            do {
                try audioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.asset.duration), of: audio, at: .zero)
            } catch {
                completionHandler(nil, error)
            }
        }
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.trackID = videoTrack.trackID
        
        let instruction = CompositionInstruction(trackID: videoTrack.trackID, bufferCallback: filtering)
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: self.asset.duration)
        instruction.layerInstructions = [layerInstruction]
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = Compositor.self
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        videoComposition.instructions = [instruction]
        
        guard let export = AVAssetExportSession(asset: composition, presetName: presetName) else {
            completionHandler(nil, nil)
            return
        }
        export.videoComposition = videoComposition
        export.outputURL = outputURL
        export.outputFileType = .mp4
        
        export.exportAsynchronously { [weak export] in
            guard let export = export, let outputURL = export.outputURL else { return }
            switch export.status {
            case .failed:
                DispatchQueue.main.async { completionHandler(nil, export.error) }
            case .cancelled:
                DispatchQueue.main.async { completionHandler(nil, nil) }
            case .completed:
                DispatchQueue.main.async { completionHandler(outputURL, nil) }
            default:
                break
            }
        }
    }
}
