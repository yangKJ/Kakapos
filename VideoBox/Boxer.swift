//
//  Boxer.swift
//  VideoBox
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

public struct Boxer {
    
    let asset: AVAsset
    let commands: [Command]
    
    public var presetName: String = AVAssetExportPresetHighestQuality {
        didSet {
            if !AVAssetExportSession.allExportPresets().contains(presetName) {
                presetName = AVAssetExportPresetMediumQuality
            }
        }
    }
    
    public init(videoURL: URL, commands: [Command]) {
        self.init(asset: AVAsset(url: videoURL), commands: commands)
    }
    
    public init(asset: AVAsset, commands: [Command]) {
        self.asset = asset
        self.commands = commands
    }
    
    /// Export the video.
    /// - Parameters:
    ///   - outputURL: Specifies the sandbox address of the exported video.
    ///   - completionHandler: Action completed callback.
    public func outputVideo(_ outputURL: URL, completionHandler: @escaping (_ videoURL: URL?, _ error: Error?) -> Void) {
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
        
        var audioTrack: AVMutableCompositionTrack? = nil
        if let audio = self.asset.tracks(withMediaType: .audio).first,
           let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            audioTrack = audioCompositionTrack
            do {
                try audioTrack!.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.asset.duration), of: audio, at: .zero)
            } catch {
                completionHandler(nil, error)
            }
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        
        guard let export = AVAssetExportSession(asset: composition, presetName: presetName) else {
            completionHandler(nil, nil)
            return
        }
        
        var water: WatermarkCommand?
        for item in commands {
            if let item = item as? WatermarkCommand {
                water = item
            } else {
                item.execute(export: export, tracks: (videoTrack, audioTrack), videoComposition: videoComposition)
            }
        }
        // Final treatment of watermarking
        water?.execute(export: export, tracks: (videoTrack, audioTrack), videoComposition: videoComposition)
        
        export.videoComposition = videoComposition
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        
        export.exportAsynchronously { [weak export] in
            guard let export = export else { return }
            DispatchQueue.main.async {
                switch export.status {
                case .failed:
                    completionHandler(nil, export.error)
                case .completed:
                    completionHandler(outputURL, nil)
                default:
                    completionHandler(nil, nil)
                    break
                }
            }
        }
    }
}
