//
//  VideoCompositor.swift
//  KakaposExamples
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation
import CoreVideo
import VideoToolbox

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
        String(kCVPixelBufferPixelFormatTypeKey): [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ],
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
                          var pixelBuffer = request.sourceFrame(byTrackID: trackID) else {
                        //let pixelBuffer = self.renderContext?.newPixelBuffer() else {
                        request.finish(with: VideoX.Error.newRenderedPixelBufferForRequestFailure)
                        return
                    }
//                    if instruction.orientation != .up, let cgimage = self.toCGImage(pixelBuffer: pixelBuffer) {
//                        if let buffer = self.rotateCGImage(cgimage, orientation: instruction.orientation) {
//                            pixelBuffer = buffer
//                        }
//                    }
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

extension VideoCompositor {
    
    private func toCGImage(pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
    
    private func createBlankPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        if status != kCVReturnSuccess {
            return nil
        }
        return pixelBuffer
    }
    
    private func rotateCGImage(_ image: CGImage, orientation: VideoOrientation) -> CVPixelBuffer? {
        let width = image.width, height = image.height
        guard let pixelBuffer = createBlankPixelBuffer(width: width, height: height) else {
            return nil
        }
        let bitsPerComponent = image.bitsPerComponent
        let bytesPerRow = image.bytesPerRow
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = image.bitmapInfo
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(data: pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return nil
        }
        
        // 设置转换，以旋转图像
//        let (translate, scale) = orientation.translateAndScaleBy(width: width, height: height)
//        context.translateBy(x: translate.x, y: translate.y)
//        context.rotate(by: orientation.rotate)
        //context.scaleBy(x: scale.x, y: scale.y)
        
        let rect = orientation.translateRect(width: width, height: height)
        context.draw(image, in: rect)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}
