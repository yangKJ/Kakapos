//
//  Compositor.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

class Compositor: NSObject, AVVideoCompositing {
    
    let renderQueue = DispatchQueue(label: "com.condy.exporter.renderingqueue")
    let renderContextQueue = DispatchQueue(label: "com.condy.exporter.rendercontextqueue")
    
    var renderContext: AVVideoCompositionRenderContext!
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
    ]
    
    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
    ]
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        self.renderQueue.sync {
            guard let instruction = request.videoCompositionInstruction as? CompositionInstruction else {
                request.finish(with: NSError(domain: "condy.com", code: 760, userInfo: nil))
                return
            }
            guard let pixels = request.sourceFrame(byTrackID: instruction.trackID) else {
                request.finish(with: NSError(domain: "condy.com", code: 761, userInfo: nil))
                return
            }
            
            let buffer = instruction.bufferCallback(pixels)
            request.finish(withComposedVideoFrame: buffer)
        }
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        self.renderContextQueue.sync {
            self.renderContext = newRenderContext
        }
    }
}