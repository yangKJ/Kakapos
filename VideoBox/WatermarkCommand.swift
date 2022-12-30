//
//  WatermarkCommand.swift
//  VideoBox
//
//  Created by Condy on 2022/12/30.
//

import Foundation

public struct WatermarkCommand {
    
    public let waterLayer: CALayer
    public init(layer: CALayer) {
        self.waterLayer = layer
    }
}

extension WatermarkCommand: Command {
    public func execute(export: AVAssetExportSession, tracks: Tracks, videoComposition: AVMutableVideoComposition) {
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize)
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(waterLayer)
        
        if videoComposition.instructions.isEmpty {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks.videoTrack)
            layerInstruction.trackID = tracks.videoTrack.trackID

            let duration = tracks.videoTrack.timeRange.duration
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(start: .zero, duration: duration)
            instruction.layerInstructions = [layerInstruction]

            videoComposition.instructions = [instruction]
        }
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }
}
