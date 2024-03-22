//
//  BaseInstruction.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

open class CompositionInstruction: AVMutableVideoCompositionInstruction {
    
    public var provider: Exporter.Provider?
    public var trackID: CMPersistentTrackID?
    public var compositionTrack: AVCompositionTrack?
    public var options: [Exporter.Option: Any] = [:]
    
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
            guard let value = Exporter.Option.VideoCompositionInstructionContainsTweening.has(with: options) as? Bool else {
                return false
            }
            return value
        }
    }
    
    // 子类必须实现
    open func handyPixelBuffer(_ buffer: ExporterBuffer, block: @escaping (ExporterBuffer) -> Void, compositionTime: CMTime) {
        
    }
    
    func initCompositionTrack(_ track: AVCompositionTrack, provider: Exporter.Provider, options: [Exporter.Option: Any]) {
        self.provider = provider
        self.compositionTrack = track
        self.trackID = track.trackID
        self.options = options
        self.enablePostProcessing = setupEnablePostProcessing(options: options)
        self.layerInstructions = setupLayerInstructions(options: options, track: track)
    }
    
    private func setupEnablePostProcessing(options: [Exporter.Option: Any]) -> Bool {
        if let value = Exporter.Option.VideoCompositionInstructionEnablePostProcessing.has(with: options) as? Bool {
            return value
        }
        return true
    }
    
    private func setupLayerInstructions(options: [Exporter.Option: Any], track: AVCompositionTrack) -> [AVVideoCompositionLayerInstruction] {
        if let value = Exporter.Option.VideoCompositionInstructionLayerInstructions.has(with: options) as? [AVVideoCompositionLayerInstruction] {
            return value
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.trackID = track.trackID
        return [layerInstruction]
    }
}
