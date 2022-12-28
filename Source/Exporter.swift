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
    
    let asset: AVAsset
    let commands: [ExporterCommand]
    weak var delegate: ExporterDelegate?
    
    public var presetName: String = AVAssetExportPresetHighestQuality {
        didSet {
            if !AVAssetExportSession.allExportPresets().contains(presetName) {
                presetName = AVAssetExportPresetMediumQuality
            }
        }
    }
    
    public init(videoURL: URL, delegate: ExporterDelegate, commands: [ExporterCommand]) {
        self.init(asset: AVAsset(url: videoURL), delegate: delegate, commands: commands)
    }
    
    public init(asset: AVAsset, delegate: ExporterDelegate, commands: [ExporterCommand]) {
        self.asset = asset
        self.delegate = delegate
        self.commands = commands
    }
    
    /// Export the video after injecting the filter.
    /// - Parameters:
    ///   - outputURL: Specifies the sandbox address of the exported video.
    ///   - filtering: Filters work to filter pixel buffer.
    public func exportVideo(outputURL: URL? = nil, filtering: @escaping PixelBufferCallback) {
        let outputURL = outputURL ?? creatrOutputURL()
        guard let track = self.asset.tracks(withMediaType: .video).first else {
            delegate?.export(self, failed: Exporter.Error.videoTrackEmpty)
            return
        }
        
        let composition = AVMutableComposition()
        composition.naturalSize = track.naturalSize
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            delegate?.export(self, failed: Exporter.Error.addVideoTrack)
            return
        }
        
        do {
            try videoTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.asset.duration), of: track, at: .zero)
        } catch {
            delegate?.export(self, failed: Exporter.Error.error(error))
        }
        
        if let audio = self.asset.tracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            do {
                try audioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: self.asset.duration), of: audio, at: .zero)
            } catch {
                delegate?.export(self, failed: Exporter.Error.error(error))
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
            delegate?.export(self, failed: Exporter.Error.exportSessionEmpty)
            return
        }
        export.videoComposition = videoComposition
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        
        commands.forEach { $0.execute(export: export) }
        
        export.exportAsynchronously { [weak export] in
            guard let export = export else { return }
            DispatchQueue.main.async {
                switch export.status {
                case .failed:
                    if let error = export.error {
                        delegate?.export(self, failed: Exporter.Error.error(error))
                    } else {
                        delegate?.export(self, failed: Exporter.Error.unknown)
                    }
                case .completed:
                    delegate?.export(self, success: outputURL)
                default:
                    delegate?.export(self, failed: Exporter.Error.exportAsynchronously(export.status))
                    break
                }
            }
        }
    }
}

extension Exporter {
    // Creating temp path to save the converted video
    func creatrOutputURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
        let outputURL = documentsDirectory.appendingPathComponent("condy_exporter_video.mp4")
        
        // Check if the file already exists then remove the previous file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                //completionHandler(nil, error)
            }
        }
        return outputURL
    }
}
