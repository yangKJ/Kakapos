//
//  BaseInstruction.swift
//  VideoX
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

public protocol InstructionProtocol {
    
    func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest)
}

public typealias CompositionInstruction = Instruction & InstructionProtocol
public typealias BufferBlock = (CVPixelBuffer) -> Void

open class Instruction: AVMutableVideoCompositionInstruction, @unchecked Sendable {
    
    public var provider: VideoX.Provider?
    public var trackID: CMPersistentTrackID?
    public var compositionTrack: AVCompositionTrack?
    public var options: [VideoX.Option: Any] = [:]
    
    public private(set) var minTime: CGFloat = 0.0
    public private(set) var orientation: VideoOrientation = .up
    
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
        self.orientation = provider.orientation
        self.enablePostProcessing = VideoX.Option.setupEnablePostProcessing(options: options)
        self.minTime = VideoX.Option.setupExportSessionMinTime(options: options)
        self.setup()
    }
    
    open func setup() { }
}
