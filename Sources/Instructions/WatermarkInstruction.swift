//
//  WatermarkInstruction.swift
//  Kakapos
//
//  Created by Condy on 2024/4/12.
//

import Foundation
import AVFoundation
import CoreVideo

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(Harbeth)
import Harbeth
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
    
    private let watermarkType: WatermarkType
    private let position: WatermarkPosition
    private let margin: CGFloat
    private let opacity: Float
    private let scale: CGFloat
    
    private var cachedWatermarkTexture: MTLTexture?
    private var canvasSize: CGSize?
    
    public init(type: WatermarkType, position: WatermarkPosition, margin: CGFloat = 10, opacity: Float = 1.0, scale: CGFloat = 1.0) {
        self.watermarkType = type
        self.position = position
        self.margin = margin
        self.opacity = opacity
        self.scale = scale
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func setup() {
        super.setup()
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        #if canImport(Harbeth)
        if let filter = createHarbethWatermarkFilter(buffer: buffer) {
            buffer.kaka.filtering(with: [filter], callback: block)
            return
        }
        #endif
        block(buffer)
    }
    
    #if canImport(Harbeth)
    private func createHarbethWatermarkFilter(buffer: CVPixelBuffer) -> C7FilterProtocol? {
        let width  = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let currentCanvasSize = CGSize(width: width, height: height)
        if cachedWatermarkTexture == nil || canvasSize != currentCanvasSize {
            guard let cgImage = createPositionedWatermark(canvasSize: currentCanvasSize) else {
                return nil
            }
            canvasSize = currentCanvasSize
            cachedWatermarkTexture = try? TextureLoader(with: cgImage).texture
        }
        guard let watermarkTexture = cachedWatermarkTexture else {
            return nil
        }
        return C7Blend(with: .normal, blendTexture: watermarkTexture, intensity: Float(opacity))
    }
    #endif
    
    private func createPositionedWatermark(canvasSize: CGSize) -> CGImage? {
        #if canImport(UIKit)
        switch watermarkType {
        case .image(let image):
            return createImageWatermark(image: image, canvasSize: canvasSize)
        case .text(let text, let font, let color):
            return createTextWatermark(text: text, font: font, color: color, canvasSize: canvasSize)
        }
        #elseif canImport(AppKit)
        switch watermarkType {
        case .image(let image):
            return createImageWatermark(image: image, canvasSize: canvasSize)
        case .text(let text, let font, let color):
            return createTextWatermark(text: text, font: font, color: color, canvasSize: canvasSize)
        }
        #else
        return nil
        #endif
    }
    
    #if canImport(UIKit)
    private func createImageWatermark(image: UIImage, canvasSize: CGSize) -> CGImage? {
        let scaledImage = scale == 1.0 ? image : scaleImage(image: image)
        let watermarkSize = scaledImage.size
        let origin = position.origin(watermarkSize: watermarkSize, canvasSize: canvasSize, margin: margin)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        scaledImage.draw(at: origin)
        return context.makeImage()
    }
    
    private func scaleImage(image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    private func createTextWatermark(text: String, font: UIFont, color: UIColor, canvasSize: CGSize) -> CGImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let scaledSize = CGSize(width: textSize.width * scale, height: textSize.height * scale)
        let origin = position.origin(watermarkSize: scaledSize, canvasSize: canvasSize, margin: margin)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        (text as NSString).draw(at: origin, withAttributes: attributes)
        return context.makeImage()
    }
    #elseif canImport(AppKit)
    private func createImageWatermark(image: NSImage, canvasSize: CGSize) -> CGImage? {
        let scaledImage = scale == 1.0 ? image : createScaledImage(image: image)
        let watermarkSize = scaledImage.size
        let origin = position.origin(watermarkSize: watermarkSize, canvasSize: canvasSize, margin: margin)
        let canvasImage = NSImage(size: canvasSize)
        canvasImage.lockFocus()
        defer { canvasImage.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        let rect = CGRect(origin: origin, size: watermarkSize)
        scaledImage.draw(in: rect)
        return canvasImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    private func createTextWatermark(text: String, font: NSFont, color: NSColor, canvasSize: CGSize) -> CGImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let scaledSize = NSSize(width: textSize.width * scale, height: textSize.height * scale)
        let origin = position.origin(watermarkSize: scaledSize, canvasSize: canvasSize, margin: margin)
        let canvasImage = NSImage(size: canvasSize)
        canvasImage.lockFocus()
        defer { canvasImage.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        (text as NSString).draw(at: origin, withAttributes: attributes)
        return canvasImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    private func createScaledImage(image: NSImage) -> NSImage {
        let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        defer { scaledImage.unlockFocus() }
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        return scaledImage
    }
    #endif
}
