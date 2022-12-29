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
    let bufferCallback: VideoExporter.PixelBufferCallback
    
    override var requiredSourceTrackIDs: [NSValue] {
        get {
            return [NSNumber(value: Int(self.trackID))]
        }
    }
    override var containsTweening: Bool {
        get {
            return false
        }
    }
    
    init(trackID: CMPersistentTrackID, bufferCallback: @escaping VideoExporter.PixelBufferCallback) {
        self.trackID = trackID
        self.bufferCallback = bufferCallback
        super.init()
        self.enablePostProcessing = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
