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

final class VideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    
    let renderQueue = DispatchQueue(label: "com.condy.exporter.rendering.queue")
    
    var renderContext: AVVideoCompositionRenderContext?
    var shouldCancelAllRequests = false
    #if os(macOS)
    var sourcePixelBufferAttributes: [String : Sendable]? = [
        String(kCVPixelBufferPixelFormatTypeKey): [kCVPixelFormatType_32BGRA]
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Sendable] = [
        String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
    ]
    #else
    var sourcePixelBufferAttributes: [String : Sendable]? = [
        String(kCVPixelBufferPixelFormatTypeKey): [kCVPixelFormatType_32BGRA],
        String(kCVPixelBufferOpenGLESCompatibilityKey): true
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Sendable] = [
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
                          let renderContext = self.renderContext else {
                        request.finish(with: VideoX.Error.newRenderedPixelBufferForRequestFailure)
                        return
                    }
                    let renderSize = renderContext.size
                    
                    let callback = { buffer in
                        request.finish(withComposedVideoFrame: buffer)
                    }
                    
                    // 只处理单轨道
                    if let trackID = instruction.trackID, let pixelBuffer = request.sourceFrame(byTrackID: trackID) {
                        let transformedBuffer = self.applyTransform(to: pixelBuffer, renderSize: renderSize, instruction: instruction)
                        if let transformedBuffer = transformedBuffer {
                            instruction.operationPixelBuffer(transformedBuffer, block: callback, for: request)
                        } else {
                            instruction.operationPixelBuffer(pixelBuffer, block: callback, for: request)
                        }
                    } else {
                        request.finish(with: VideoX.Error.newRenderedPixelBufferForRequestFailure)
                    }
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
    
    private func applyTransform(to pixelBuffer: CVPixelBuffer, renderSize: CGSize, instruction: CompositionInstruction) -> CVPixelBuffer? {
        if let rotationAngle = getRotationAngle(from: instruction) {
            let isMovVideo = isMovVideo(instruction)
            return processRotation(pixelBuffer, rotationAngle: rotationAngle, renderSize: renderSize, isMovVideo: isMovVideo)
        }
        if !isMovVideo(instruction) {
            return nil
        }
        /// Fix mov format video of rotating 90 to the left.
        return processRotation(pixelBuffer, rotationAngle: .angle0, renderSize: renderSize, isMovVideo: true)
    }
    
    private func getRotationAngle(from instruction: CompositionInstruction) -> RotationAngle? {
        if let compositeInstruction = instruction as? CompositeInstruction {
            for subInstruction in compositeInstruction.instructions {
                if let rotateInstruction = subInstruction as? RotateInstruction {
                    return rotateInstruction.rotationAngle
                }
            }
        } else if let rotateInstruction = instruction as? RotateInstruction {
            return rotateInstruction.rotationAngle
        }
        return nil
    }
    
    private func isMovVideo(_ instruction: CompositionInstruction) -> Bool {
        if let provider = instruction.provider {
            return provider.orientation == .right
        }
        return false
    }
    
    private func processRotation(_ pixelBuffer: CVPixelBuffer, rotationAngle: RotationAngle, renderSize: CGSize, isMovVideo: Bool) -> CVPixelBuffer? {
        guard let cgImage = toCGImage(pixelBuffer: pixelBuffer) else {
            return nil
        }
        let outputWidth  = Int(renderSize.width)
        let outputHeight = Int(renderSize.height)
        guard let outputPixelBuffer = createBlankPixelBuffer(width: outputWidth, height: outputHeight) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputPixelBuffer, []) }
        
        guard let pixelData = CVPixelBufferGetBaseAddress(outputPixelBuffer) else {
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputPixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: pixelData,
                                      width: outputWidth,
                                      height: outputHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        
        if let (transX, transY, rotate) = rotationAngle.rotation(isMovVideo: isMovVideo, renderSize: renderSize) {
            context.translateBy(x: transX, y: transY)
            context.rotate(by: rotate)
        }
        
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.draw(cgImage, in: imageRect)
        
        return outputPixelBuffer
    }
}
