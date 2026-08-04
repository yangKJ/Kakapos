//
//  WatermarkInstruction.swift
//  Kakapos
//
//  Created by Condy on 2024/4/12.
//

import Foundation
import KakaposMediaCore
import AVFoundation
import CoreImage
import CoreText
import CoreVideo

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum WatermarkPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    case custom(x: CGFloat, y: CGFloat)
    
    func origin(watermarkSize: CGSize, canvasSize: CGSize, margin: CGFloat) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: margin, y: margin)
        case .topRight:
            return CGPoint(x: canvasSize.width - watermarkSize.width - margin, y: margin)
        case .bottomLeft:
            return CGPoint(x: margin, y: canvasSize.height - watermarkSize.height - margin)
        case .bottomRight:
            return CGPoint(x: canvasSize.width - watermarkSize.width - margin, y: canvasSize.height - watermarkSize.height - margin)
        case .center:
            return CGPoint(x: (canvasSize.width - watermarkSize.width) / 2, y: (canvasSize.height - watermarkSize.height) / 2)
        case .custom(let x, let y):
            return CGPoint(x: x, y: y)
        }
    }
}

#if canImport(UIKit)
public enum WatermarkType {
    case image(UIImage)
    case text(String, font: UIFont, color: UIColor)
}
#elseif canImport(AppKit)
public enum WatermarkType {
    case image(NSImage)
    case text(String, font: NSFont, color: NSColor)
}
#endif

public final class WatermarkInstruction: CompositionInstruction, @unchecked Sendable {

    public enum RenderingError: Error, Equatable {
        case instructionReleased
        case pixelBufferUnavailable
        case watermarkImageUnavailable
        case unsupportedDynamicRange
        case outputPixelBufferCreationFailed(CVReturn)
    }

    /// 传统 video-composition 回调无法返回错误，因此失败时会回退原帧并通过该闭包报告。
    public var renderingFailureHandler: (@Sendable (RenderingError) -> Void)?
    
    private let watermarkType: WatermarkType
    private let position: WatermarkPosition
    private let margin: CGFloat
    private let opacity: Float
    private let scale: CGFloat

    private let renderContext = CIContext(options: [.cacheIntermediates: false])
    private let cacheLock = NSLock()
    private var cachedWatermarkContent: WatermarkContent?
    private var cachedOutputPool: CVPixelBufferPool?
    private var cachedOutputSize: CGSize?
    
    public init(type: WatermarkType, position: WatermarkPosition, margin: CGFloat = 10, opacity: Float = 1.0, scale: CGFloat = 1.0) {
        self.watermarkType = type
        self.position = position
        self.margin = margin
        self.opacity = min(max(opacity, 0), 1)
        self.scale = scale.isFinite && scale > 0 ? scale : 1
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func setup() {
        super.setup()
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        do {
            block(try renderWatermark(on: buffer))
        } catch let error as RenderingError {
            renderingFailureHandler?(error)
            block(buffer)
        } catch {
            renderingFailureHandler?(.watermarkImageUnavailable)
            block(buffer)
        }
    }

    private func renderWatermark(on buffer: CVPixelBuffer) throws -> CVPixelBuffer {
        guard Self.isHighDynamicRange(buffer) == false else {
            throw RenderingError.unsupportedDynamicRange
        }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let currentCanvasSize = CGSize(width: width, height: height)
        guard let content = watermarkContent() else {
            throw RenderingError.watermarkImageUnavailable
        }
        let outputBuffer = try makeOutputBuffer(size: currentCanvasSize)

        let sourceImage = CIImage(cvPixelBuffer: buffer)
        let topLeftOrigin = position.origin(
            watermarkSize: content.size,
            canvasSize: currentCanvasSize,
            margin: margin
        )
        let overlayImage = content.image.transformed(by: CGAffineTransform(
            translationX: topLeftOrigin.x,
            y: currentCanvasSize.height - topLeftOrigin.y - content.size.height
        ))
        let outputImage = overlayImage.composited(over: sourceImage)
        renderContext.render(
            outputImage,
            to: outputBuffer,
            bounds: sourceImage.extent,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        Self.copySDRAttachments(from: buffer, to: outputBuffer)
        return outputBuffer
    }

    private func watermarkContent() -> WatermarkContent? {
        cacheLock.lock()
        if let cachedWatermarkContent {
            cacheLock.unlock()
            return cachedWatermarkContent
        }
        let content = createWatermarkContent()
        cachedWatermarkContent = content
        cacheLock.unlock()
        return content
    }

    private func createWatermarkContent() -> WatermarkContent? {
        #if canImport(UIKit)
        switch watermarkType {
        case .image(let image):
            guard let source = CIImage(image: image) else { return nil }
            return scaledContent(image: source, targetSize: image.size)
        case .text(let text, let font, let color):
            return createTextContent(
                text: text,
                fontName: font.fontName,
                fontSize: font.pointSize,
                color: color.cgColor
            )
        }
        #elseif canImport(AppKit)
        switch watermarkType {
        case .image(let image):
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return scaledContent(image: CIImage(cgImage: cgImage), targetSize: image.size)
        case .text(let text, let font, let color):
            return createTextContent(
                text: text,
                fontName: font.fontName,
                fontSize: font.pointSize,
                color: color.cgColor
            )
        }
        #else
        return nil
        #endif
    }

    private func scaledContent(image: CIImage, targetSize: CGSize) -> WatermarkContent? {
        let extent = image.extent.integral
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        guard extent.isInfinite == false, extent.isEmpty == false,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let resized = normalized.transformed(by: CGAffineTransform(
            scaleX: size.width / extent.width,
            y: size.height / extent.height
        ))
        return WatermarkContent(image: applyingOpacity(to: resized), size: size)
    }

    private func createTextContent(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        color: CGColor
    ) -> WatermarkContent? {
        let font = CTFontCreateWithName(fontName as CFString, fontSize * scale, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: attributes
        ))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let watermarkSize = CGSize(
            width: ceil(width),
            height: ceil(ascent + descent + leading)
        )
        guard let image = createWatermarkImage(size: watermarkSize, draw: { context in
            context.textPosition = CGPoint(x: 0, y: descent + leading)
            CTLineDraw(line, context)
        }) else { return nil }
        return WatermarkContent(image: applyingOpacity(to: CIImage(cgImage: image)), size: watermarkSize)
    }

    private func createWatermarkImage(
        size: CGSize,
        draw: (CGContext) -> Void
    ) -> CGImage? {
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: size))
        draw(context)
        return context.makeImage()
    }

    private func applyingOpacity(to image: CIImage) -> CIImage {
        guard opacity < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
        ])
    }

    private func makeOutputBuffer(size: CGSize) throws -> CVPixelBuffer {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cachedOutputSize != size || cachedOutputPool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
                attributes as CFDictionary,
                &pool
            )
            guard status == kCVReturnSuccess, let pool else {
                throw RenderingError.outputPixelBufferCreationFailed(status)
            }
            cachedOutputPool = pool
            cachedOutputSize = size
        }
        guard let outputPool = cachedOutputPool else {
            throw RenderingError.outputPixelBufferCreationFailed(kCVReturnInvalidPoolAttributes)
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            outputPool,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw RenderingError.outputPixelBufferCreationFailed(status)
        }
        return buffer
    }

    private static func isHighDynamicRange(_ buffer: CVPixelBuffer) -> Bool {
        let attachment: CFTypeRef?
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            attachment = CVBufferCopyAttachment(
                buffer,
                kCVImageBufferTransferFunctionKey,
                nil
            )
        } else {
            attachment = CVBufferGetAttachment(
                buffer,
                kCVImageBufferTransferFunctionKey,
                nil
            )?.takeUnretainedValue()
        }
        guard let attachment else { return false }
        let transfer = attachment as? String
        return transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
            || transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
    }

    private static func copySDRAttachments(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        CVBufferPropagateAttachments(source, destination)
        CVBufferSetAttachment(
            destination,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            destination,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_sRGB,
            .shouldPropagate
        )
        CVBufferRemoveAttachment(destination, kCVImageBufferYCbCrMatrixKey)
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(
                destination,
                kCVImageBufferCGColorSpaceKey,
                colorSpace,
                .shouldPropagate
            )
        }
    }
}

private struct WatermarkContent {
    let image: CIImage
    let size: CGSize
}

extension WatermarkInstruction: FrameProcessorProvidingInstruction {
    var kakaposFrameProcessor: FrameProcessor? {
        ClosureFrameProcessor { [weak self] frame, completion in
            guard let self else {
                completion(.failure(RenderingError.instructionReleased))
                return
            }
            guard let pixelBuffer = extractPixelBuffer(frame) else {
                completion(.failure(RenderingError.pixelBufferUnavailable))
                return
            }
            do {
                let outputBuffer = try self.renderWatermark(on: pixelBuffer)
                completion(.success(PixelBufferFrame(
                    pixelBuffer: outputBuffer,
                    metadata: frame.metadata
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
