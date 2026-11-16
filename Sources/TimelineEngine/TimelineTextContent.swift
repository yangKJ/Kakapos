// 作者：Condy
import CoreImage
import CoreText
import Foundation
import QuartzCore

/// 文本内容只光栅化一次；时间窗、父子状态和逐字动画在每帧解析求值。
final class TimelineTextContent {
    private struct Glyph {
        let image: CIImage
        let frame: CGRect
        let index: Int
    }
    private let content: CIImage
    private let background: CIImage
    private let glyphs: [Glyph]
    let size: CGSize
    private let bounds: CGRect
    private let masksToBounds: Bool
    private let cornerRadius: CGFloat

    init(_ layer: TextLayer) throws {
        guard layer.frame.width.isFinite, layer.frame.height.isFinite, layer.frame.width >= 0, layer.frame.height >= 0,
              layer.contentsScale.isFinite else { throw CocoaError(.coderInvalidValue) }
        size = layer.frame.size
        bounds = CGRect(origin: .zero, size: layer.frame.size)
        masksToBounds = layer.masksToBounds
        cornerRadius = layer.cornerRadius
        let scale = max(layer.contentsScale, 1)
        let text = NSMutableAttributedString(attributedString: layer.attributedText)
        if text.length > 0 {
            var alignment: CTTextAlignment
            switch layer.alignmentMode {
            case .center: alignment = .center
            case .right: alignment = .right
            case .justified: alignment = .justified
            case .natural: alignment = .natural
            default: alignment = .left
            }
            let key = kCTParagraphStyleAttributeName as NSAttributedString.Key
            var missing: [NSRange] = []
            text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if value == nil { missing.append(range) }
            }
            withUnsafePointer(to: &alignment) { pointer in
                var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
                let style = CTParagraphStyleCreate(&setting, 1)
                missing.forEach { text.addAttribute(key, value: style, range: $0) }
            }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length), CGPath(rect: bounds, transform: nil), nil)
        func raster(_ size: CGSize, draw: (CGContext) -> Void) throws -> CIImage {
            let w = max(1, ceil(size.width * scale)); let h = max(1, ceil(size.height * scale))
            guard w.isFinite, h.isFinite, w <= CGFloat(Int.max / 4), h <= CGFloat(Int.max / 4),
                  w <= CGFloat(Int.max / 4) / h else { throw CocoaError(.coderInvalidValue) }
            let width = Int(w); let height = Int(h)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw CocoaError(.coderInvalidValue)
            }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
            return CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        }
        let localBounds = bounds
        let radius = cornerRadius
        background = try raster(bounds.size) { context in
            if let color = layer.backgroundColor {
                context.setFillColor(color)
                context.addPath(CGPath(roundedRect: localBounds, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.fillPath()
            }
        }
        content = try raster(bounds.size) { context in
            if layer.masksToBounds {
                context.addPath(CGPath(roundedRect: localBounds, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.clip()
            }
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
        }
        #if canImport(UIKit)
        let animates = layer.animationStyle == .opacity
        #else
        let animates = false
        #endif
        guard animates else { glyphs = []; return }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let string = text.string as NSString
        var characters: [NSRange] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byComposedCharacterSequences) { _, range, _, _ in characters.append(range) }
        var values: [Glyph] = []
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            for (index, range) in characters.enumerated() where range.location >= lineRange.location && range.location < lineRange.location + lineRange.length {
                let fragment = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
                var ascent: CGFloat = 0; var descent: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(fragment, &ascent, &descent, nil))
                let size = CGSize(width: max(1, ceil(width + 2)), height: max(1, ceil(ascent + descent + 2)))
                let image = try raster(size) { context in
                    context.textMatrix = .identity; context.textPosition = CGPoint(x: 1, y: descent + 1)
                    CTLineDraw(fragment, context)
                }
                let x = origins[lineIndex].x + CTLineGetOffsetForStringIndex(line, range.location, nil) - 1
                let y = origins[lineIndex].y - descent - 1
                values.append(Glyph(image: image, frame: CGRect(origin: CGPoint(x: x, y: y), size: size), index: index))
            }
        }
        glyphs = values
    }

    func image(at time: Double) -> CIImage {
        guard !glyphs.isEmpty else { return content.composited(over: background) }
        var result = background
        for glyph in glyphs {
            let progress = CGFloat(max(0, min((time - Double(glyph.index) * 0.125) / 0.125, 1)))
            guard progress > 0 else { continue }
            let rect = glyph.frame
            let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: progress, y: progress).translatedBy(x: -rect.width / 2, y: -rect.height / 2)
            let image = glyph.image.transformed(by: transform).applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: progress)
            ])
            result = image.composited(over: result)
        }
        // 动画碎片沿用原文字容器的裁切和圆角。
        if masksToBounds {
            let mask = CIImage(color: .white).cropped(to: bounds)
            result = result.cropped(to: bounds)
            if cornerRadius > 0 {
                let rounded = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                    "inputExtent": CIVector(cgRect: bounds), "inputRadius": cornerRadius, "inputColor": CIColor.white
                ])?.outputImage ?? mask
                result = result.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear), kCIInputMaskImageKey: rounded])
            }
        }
        return result
    }
}
