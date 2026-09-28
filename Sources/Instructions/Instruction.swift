//
//  BaseInstruction.swift
//  VideoX
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

open class Instruction: AVMutableVideoCompositionInstruction {
    
    public var provider: VideoX.Provider?
    public var trackID: CMPersistentTrackID?
    public var compositionTrack: AVCompositionTrack?
    public var options: [VideoX.Option: Any] = [:]
    
    public private(set) var minTime: CGFloat = 0.0
    
    open override var requiredSourceTrackIDs: [NSValue] {
        get {
            guard let trackID = trackID else {
                return []
            }
            return [NSNumber(value: Int(trackID))]
        }
    }
    
    open override var containsTweening: Bool {
        get {
            guard let value = VideoX.Option.VideoCompositionInstructionContainsTweening.has(with: options) as? Bool else {
                return false
            }
            return value
        }
    }
    
    func initCompositionTrack(_ track: AVCompositionTrack, provider: VideoX.Provider, options: [VideoX.Option: Any]) {
        self.provider = provider
        self.compositionTrack = track
        self.trackID = track.trackID
        self.options = options
        self.enablePostProcessing = setupEnablePostProcessing(options: options)
        self.layerInstructions = setupLayerInstructions(options: options, track: track)
        self.minTime = VideoX.Option.setupExportSessionMinTime(options: options)
    }
    
    private func setupEnablePostProcessing(options: [VideoX.Option: Any]) -> Bool {
        if let value = VideoX.Option.VideoCompositionInstructionEnablePostProcessing.has(with: options) as? Bool {
            return value
        }
        return true
    }
    
    private func setupLayerInstructions(options: [VideoX.Option: Any], track: AVCompositionTrack) -> [AVVideoCompositionLayerInstruction] {
        if let value = VideoX.Option.VideoCompositionInstructionLayerInstructions.has(with: options) as? [AVVideoCompositionLayerInstruction] {
            return value
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.trackID = track.trackID
        return [layerInstruction]
    }
}
