// 作者：Condy
import Foundation
import AVFoundation
import CoreGraphics

/// 各分量保留所在时间轴的局部坐标，避免展开图层后丢失父子曲线。
struct TimelineLayerComponent {
    let timeOffset: CMTime
    let opacity: Float
    let transform: CGAffineTransform
    let keyframes: [KeyframeAnimation]
    let index: TimelineKeyframeIndex

    init(timeOffset: CMTime, opacity: Float, transform: CGAffineTransform, keyframes: [KeyframeAnimation]) {
        self.timeOffset = timeOffset
        self.opacity = opacity
        self.transform = transform
        self.keyframes = keyframes
        self.index = TimelineKeyframeIndex(keyframes)
    }

    func shifted(by offset: CMTime) -> TimelineLayerComponent {
        TimelineLayerComponent(timeOffset: timeOffset + offset, opacity: opacity, transform: transform, keyframes: keyframes)
    }

    func opacity(at time: CMTime) -> Float { index.value(for: "opacity", at: time - timeOffset) ?? opacity }
    func transform(at time: CMTime) -> CGAffineTransform {
        Self.transform(base: transform, index: index, at: time - timeOffset)
    }

    static func transform(base: CGAffineTransform, index: TimelineKeyframeIndex, at time: CMTime) -> CGAffineTransform {
        func value(_ key: String) -> CGFloat? { index.value(for: key, at: time).map(CGFloat.init) }
        let tx = value("translation.x") ?? value("transform.tx")
        let ty = value("translation.y") ?? value("transform.ty")
        let scale = value("scale")
        let sx = value("scale.x") ?? scale
        let sy = value("scale.y") ?? scale
        let angle = value("rotation")
        guard tx != nil || ty != nil || sx != nil || sy != nil || angle != nil else { return base }
        // QR 分解保留镜像符号和剪切；仅平移时完全保留原始线性矩阵。
        if sx == nil && sy == nil && angle == nil {
            return CGAffineTransform(a: base.a, b: base.b, c: base.c, d: base.d, tx: tx ?? base.tx, ty: ty ?? base.ty)
        }
        let determinant = base.a * base.d - base.b * base.c
        let baseX = hypot(base.a, base.b)
        let baseY: CGFloat
        let rotation: CGFloat
        let shear: CGFloat
        if baseX > 0 {
            baseY = determinant / baseX
            rotation = atan2(base.b, base.a)
            shear = (base.a * base.c + base.b * base.d) / baseX
        } else {
            baseY = hypot(base.c, base.d)
            rotation = baseY > 0 ? atan2(-base.c, base.d) : 0
            shear = 0
        }
        let c = cos(angle ?? rotation)
        let s = sin(angle ?? rotation)
        return CGAffineTransform(a: c * (sx ?? baseX), b: s * (sx ?? baseX),
            c: c * shear - s * (sy ?? baseY), d: s * shear + c * (sy ?? baseY),
            tx: tx ?? base.tx, ty: ty ?? base.ty)
    }
}

enum TimelineLayerNormalizer {
    static func compose(_ parent: CGAffineTransform, _ child: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: parent.a * child.a + parent.c * child.b,
            b: parent.b * child.a + parent.d * child.b,
            c: parent.a * child.c + parent.c * child.d,
            d: parent.b * child.c + parent.d * child.d,
            tx: parent.a * child.tx + parent.c * child.ty + parent.tx,
            ty: parent.b * child.tx + parent.d * child.ty + parent.ty)
    }

    static func flatten(_ layers: [TimelineLayer], offset: CMTime = .zero, level: Int = 0,
        ancestors: [TimelineLayerComponent] = []) -> [TimelineLayer] {
        layers.flatMap { layer -> [TimelineLayer] in
            if let group = layer as? GroupLayer {
                let start = offset + group.timeRange.start
                let component = TimelineLayerComponent(timeOffset: start, opacity: group.opacity,
                    transform: group.transform, keyframes: group.keyframes)
                return flatten(group.layers, offset: start, level: level + group.layerLevel, ancestors: ancestors + [component])
            }
            let shifted = layer.applyingOffset(offset, inheritedLevel: level)
            let component = TimelineLayerComponent(timeOffset: offset, opacity: layer.opacity,
                transform: layer.transform, keyframes: layer.keyframes)
            shifted.evaluationComponents = ancestors + (layer.evaluationComponents.isEmpty ? [component] : layer.evaluationComponents.map { $0.shifted(by: offset) })
            shifted.opacity = shifted.evaluationComponents.reduce(1) { $0 * $1.opacity }
            shifted.transform = shifted.evaluationComponents.reduce(.identity) { compose($0, $1.transform) }
            shifted.keyframes = shifted.evaluationComponents.flatMap { component in
                component.keyframes.map { $0.applyingOffset(component.timeOffset) }
            }
            return [shifted]
        }
    }
}
