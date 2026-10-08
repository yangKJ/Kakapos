//
//  VideoCompositor.swift
//  KakaposExamples
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import KakaposMediaCore
import AVFoundation
import CoreVideo
import CoreImage

final class VideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    
    let renderQueue = DispatchQueue(label: "com.condy.exporter.rendering.queue")
    
    var renderContext: AVVideoCompositionRenderContext?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var requests: [UUID: (AVAsynchronousVideoCompositionRequest, FrameProcessingOperation?)] = [:]
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
    
    private struct Transfer<Value>: @unchecked Sendable { let value: Value }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let transfer = Transfer(value: request)
        renderQueue.async {
            let request = transfer.value
            guard let instruction = request.videoCompositionInstruction as? CompositionInstruction,
                  let renderContext = self.renderContext,
                  let trackID = instruction.trackID,
                  let buffer = request.sourceFrame(byTrackID: trackID) else {
                request.finish(with: VideoX.Error.newRenderedPixelBufferForRequestFailure)
                return
            }
            let id = UUID()
            self.requests[id] = (request, nil)
            let transformed = self.applyTransform(to: buffer, renderSize: renderContext.size, instruction: instruction) ?? buffer
            let operation = executeInstruction(instruction, buffer: transformed, request: request) { result in
                let resultTransfer = Transfer(value: result)
                self.renderQueue.async {
                    guard self.requests.removeValue(forKey: id) != nil else { return }
                    switch resultTransfer.value {
                    case .success(let output): request.finish(withComposedVideoFrame: output)
                    case .failure(let error): request.finish(with: error)
                    }
                }
            }
            self.requests[id] = (request, operation)
        }
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        self.renderQueue.sync {
            self.renderContext = newRenderContext
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.async {
            let pending = self.requests.values
            self.requests.removeAll()
            pending.forEach { request, operation in
                operation?.cancel()
                request.finishCancelledRequest()
            }
        }
    }

}

extension VideoCompositor {
    
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
        InstructionTreeTraversal.firstRotationAngle(in: [instruction])
    }
    
    private func isMovVideo(_ instruction: CompositionInstruction) -> Bool {
        if let provider = instruction.provider {
            return provider.orientation == .right
        }
        return false
    }
    
    private func processRotation(_ pixelBuffer: CVPixelBuffer, rotationAngle: RotationAngle, renderSize: CGSize, isMovVideo: Bool) -> CVPixelBuffer? {
        guard let output = renderContext?.newPixelBuffer() else { return nil }
        var transform = CGAffineTransform.identity
        if let (x, y, angle) = rotationAngle.rotation(isMovVideo: isMovVideo, renderSize: renderSize) {
            transform = transform.translatedBy(x: x, y: y).rotated(by: angle)
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: transform)
        imageContext.render(image, to: output, bounds: CGRect(origin: .zero, size: renderSize), colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }
}
