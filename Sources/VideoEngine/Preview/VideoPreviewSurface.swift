//
//  VideoPreviewSurface.swift
//  Kakapos
//
//  Created by Condy on 2026/8/5.
//

#if canImport(UIKit) && canImport(MetalKit)
import AVFoundation
import CoreImage
import KakaposMediaCore
import MetalKit
import UIKit

/// 原片与处理态共用的 Metal 显示面。新 generation 等待首帧期间保留上一稳定画面。
public final class VideoPreviewSurface: MTKView, MTKViewDelegate {
    public typealias PresentationHandler = (
        VideoPreviewGeneration,
        VideoPreviewModeIdentity,
        CMTime
    ) -> Void

    private struct Submission: @unchecked Sendable {
        let frame: MediaFrame
        let generation: VideoPreviewGeneration
        let identity: VideoPreviewModeIdentity

        var metadata: FrameMetadata { frame.metadata }
    }

    public var framePresented: PresentationHandler?
    public var framePresentationFailed: ((VideoPreviewGeneration, VideoPreviewModeIdentity) -> Void)?

    private let stateLock = NSLock()
    private var acceptedGeneration = VideoPreviewGeneration(rawValue: 0)
    private var acceptedIdentity = VideoPreviewModeIdentity.original
    private var displayedSubmission: Submission?
    private var pendingSubmission: Submission?
    private var context: CIContext!
    private var colorSpace: CGColorSpace!
    private var commandQueue: MTLCommandQueue?

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        let resolvedDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: resolvedDevice)
        configure(device: resolvedDevice)
    }

    public required init(coder: NSCoder) {
        let resolvedDevice = MTLCreateSystemDefaultDevice()
        super.init(coder: coder)
        device = resolvedDevice
        configure(device: resolvedDevice)
    }

    func awaitFirstFrame(
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    ) {
        stateLock.lock()
        acceptedGeneration = generation
        acceptedIdentity = identity
        pendingSubmission = nil
        stateLock.unlock()
    }

    func submit(
        frame: MediaFrame,
        generation: VideoPreviewGeneration,
        identity: VideoPreviewModeIdentity
    ) {
        stateLock.lock()
        guard generation == acceptedGeneration, identity == acceptedIdentity else {
            stateLock.unlock()
            return
        }
        pendingSubmission = Submission(
            frame: frame,
            generation: generation,
            identity: identity
        )
        stateLock.unlock()
        requestDisplay()
    }

    func cancelPresentation() {
        stateLock.lock()
        acceptedGeneration = VideoPreviewGeneration(rawValue: acceptedGeneration.rawValue &+ 1)
        pendingSubmission = nil
        displayedSubmission = nil
        stateLock.unlock()
        requestDisplay()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestDisplay()
    }

    public func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let drawable = currentDrawable else { return }
        let submission = submissionForDrawing()
        guard let submission else {
            clear(drawable: drawable, commandBuffer: commandBuffer)
            return
        }
        let bounds = CGRect(origin: .zero, size: drawableSize)
        guard let image = fittedImage(for: submission, in: bounds) else {
            clear(drawable: drawable, commandBuffer: commandBuffer)
            reportFailure(for: submission)
            return
        }
        context.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            guard commandBuffer.status == .completed else {
                self?.reportFailure(for: submission)
                return
            }
            guard let self, self.accepts(submission) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.accepts(submission) else { return }
                self.framePresented?(
                    submission.generation,
                    submission.identity,
                    submission.metadata.presentationTime
                )
            }
        }
        commandBuffer.commit()
    }

    private func configure(device: MTLDevice?) {
        guard let device else { return }
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
        context = CIContext(mtlDevice: device)
        colorSpace = CGColorSpaceCreateDeviceRGB()
        commandQueue = device.makeCommandQueue()
    }

    private func requestDisplay() {
        if Thread.isMainThread {
            setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
        }
    }

    private func submissionForDrawing() -> Submission? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let pendingSubmission,
           pendingSubmission.generation == acceptedGeneration,
           pendingSubmission.identity == acceptedIdentity {
            displayedSubmission = pendingSubmission
            self.pendingSubmission = nil
        }
        return displayedSubmission
    }

    private func accepts(_ submission: Submission) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return submission.generation == acceptedGeneration
            && submission.identity == acceptedIdentity
            && displayedSubmission?.generation == submission.generation
            && displayedSubmission?.identity == submission.identity
    }

    private func reportFailure(for submission: Submission) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.accepts(submission) else { return }
            self.framePresentationFailed?(submission.generation, submission.identity)
        }
    }

    private func fittedImage(for submission: Submission, in bounds: CGRect) -> CIImage? {
        let sourceImage: CIImage?
        if let pixelBuffer = extractPixelBuffer(submission.frame) {
            sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        } else if let textureFrame = submission.frame as? TextureFrame,
                  let texture = extractTexture(textureFrame) {
            let textureImage = CIImage(
                mtlTexture: texture,
                options: [.colorSpace: colorSpace as Any]
            )
            sourceImage = textureFrame.coordinateSpace == .pixelBuffer
                ? textureImage?.oriented(.downMirrored)
                : textureImage
        } else {
            sourceImage = nil
        }
        guard let sourceImage else { return nil }
        let transformed = sourceImage.transformed(by: submission.metadata.trackTransform)
        let extent = transformed.extent.integral
        guard !extent.isInfinite, !extent.isEmpty else { return nil }
        let normalized = transformed.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let scale = min(
            bounds.width / normalized.extent.width,
            bounds.height / normalized.extent.height
        )
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(
            translationX: bounds.midX - scaled.extent.midX,
            y: bounds.midY - scaled.extent.midY
        ))
        return centered
            .composited(over: CIImage(color: .black).cropped(to: bounds))
            .cropped(to: bounds)
    }

    private func clear(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        guard let descriptor = currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
