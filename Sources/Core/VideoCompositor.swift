//
//  VideoCompositor.swift
//  KakaposExamples
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo

final class VideoCompositor: NSObject, AVVideoCompositing {
    
    let renderQueue = DispatchQueue(label: "com.condy.exporter.rendering.queue")
    
    var renderContext: AVVideoCompositionRenderContext?
    var shouldCancelAllRequests = false
    #if os(macOS)
    var sourcePixelBufferAttributes: [String : Any]? = [
        String(kCVPixelBufferPixelFormatTypeKey): [kCVPixelFormatType_32BGRA]
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
    ]
    #else
    var sourcePixelBufferAttributes: [String : Any]? = [
        String(kCVPixelBufferPixelFormatTypeKey): [kCVPixelFormatType_32BGRA],
        String(kCVPixelBufferOpenGLESCompatibilityKey): true
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
        String(kCVPixelBufferOpenGLESCompatibilityKey): true
    ]
    #endif
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            self.renderQueue.async {
                if self.shouldCancelAllRequests {
                    request.finishCancelledRequest()
                } else {
                    guard let instruction = request.videoCompositionInstruction as? CompositionInstruction,
                          let trackID = instruction.trackID,
                          let pixelBuffer = request.sourceFrame(byTrackID: trackID) else {
                        //let pixelBuffer = self.renderContext?.newPixelBuffer() else {
                        request.finish(with: VideoX.Error.newRenderedPixelBufferForRequestFailure)
                        return
                    }
                    let callback = { buffer in
                        request.finish(withComposedVideoFrame: buffer)
                    }
                    instruction.operationPixelBuffer(pixelBuffer, block: callback, for: request)
                }
            }
        }
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        self.renderQueue.sync {
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
