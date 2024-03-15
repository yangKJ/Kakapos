//
//  CompositionInstruction.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

class CompositionInstruction: AVMutableVideoCompositionInstruction {
    
    let trackID: CMPersistentTrackID
    let videoTrack: AVCompositionTrack
    let pixelBufferCallback: PixelBufferCallback
    let options: [Exporter.Option: Any]
    
    override var requiredSourceTrackIDs: [NSValue] {
        get {
            [NSNumber(value: Int(self.trackID))]
        }
    }
    
    override var containsTweening: Bool {
        get {
            guard let value = Exporter.Option.VideoCompositionInstructionContainsTweening.has(with: options) as? Bool else {
                return false
            }
            return value
        }
    }
    
    init(videoTrack: AVCompositionTrack, filtering: @escaping PixelBufferCallback, options: [Exporter.Option: Any]) {
        self.trackID = videoTrack.trackID
        self.videoTrack = videoTrack
        self.pixelBufferCallback = filtering
        self.options = options
        super.init()
        self.setupOptions(options)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupOptions(_ options: [Exporter.Option: Any]) {
        self.enablePostProcessing = setupEnablePostProcessing(options: options)
        self.layerInstructions = setupLayerInstructions(options: options)
    }
    
    private func setupEnablePostProcessing(options: [Exporter.Option: Any]) -> Bool {
        if let value = Exporter.Option.VideoCompositionInstructionEnablePostProcessing.has(with: options) as? Bool {
            return value
        }
        return true
    }
    
    private func setupLayerInstructions(options: [Exporter.Option: Any]) -> [AVVideoCompositionLayerInstruction] {
        if let value = Exporter.Option.VideoCompositionInstructionLayerInstructions.has(with: options) as? [AVVideoCompositionLayerInstruction] {
            return value
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.trackID = videoTrack.trackID
        return [layerInstruction]
    }
}
