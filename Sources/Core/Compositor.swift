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
    
    let renderQueue = DispatchQueue(label: "com.condy.exporter.rendering.queue")
    let renderContextQueue = DispatchQueue(label: "com.condy.exporter.rendercontext.queue")
    
    var renderContext: AVVideoCompositionRenderContext?
    var shouldCancelAllRequests = false
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
    ]
    
    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
    ]
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            self.renderQueue.async {
                if self.shouldCancelAllRequests {
                    request.finishCancelledRequest()
                } else {
                    guard let instruction = request.videoCompositionInstruction as? CompositionInstruction,
                          let trackID = instruction.trackID,
                          let pixels = request.sourceFrame(byTrackID: trackID) else {
                        return
                    }
                    let callback = { buffer in
                        request.finish(withComposedVideoFrame: buffer)
                    }
                    instruction.handyPixelBuffer(pixels, block: callback, compositionTime: request.compositionTime)
                }
            }
        }
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        self.renderContextQueue.sync {
            self.renderContext = newRenderContext
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        self.renderQueue.sync {
            shouldCancelAllRequests = true
        }
        self.renderQueue.async {
            self.shouldCancelAllRequests = false
        }
    }
}
