//
//  TimelineLayer.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics
import QuartzCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

open class TimelineLayer {
    public var timeRange: CMTimeRange
    public var layerLevel: Int
    public var opacity: Float
    public var transform: CGAffineTransform
    public var keyframes: [KeyframeAnimation]

    public init(timeRange: CMTimeRange, layerLevel: Int = 0, opacity: Float = 1, transform: CGAffineTransform = .identity, keyframes: [KeyframeAnimation] = []) {
        self.timeRange = timeRange
        self.layerLevel = layerLevel
        self.opacity = opacity
        self.transform = transform
        self.keyframes = keyframes
    }

    open func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = TimelineLayer(
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            layerLevel: layerLevel + inheritedLevel,
            opacity: opacity,
            transform: transform,
            keyframes: keyframes
        )
        return shifted
    }
}

internal struct TimelineLayerInheritance {
    let opacity: Float
    let transform: CGAffineTransform
    let keyframes: [KeyframeAnimation]

    static let identity = TimelineLayerInheritance(
        opacity: 1,
        transform: .identity,
        keyframes: []
    )

    func appending(layer: TimelineLayer) -> TimelineLayerInheritance {
        TimelineLayerInheritance(
            opacity: opacity * layer.opacity,
            transform: transform.concatenating(layer.transform),
            keyframes: keyframes + layer.keyframes
        )
    }
}

public final class ClipLayer: TimelineLayer {
    public let clipSource: AssetClipSource
    public let asset: AVAsset
    public var sourceTimeRange: CMTimeRange?
    public var volume: Float
    public var audioRamps: [AudioVolumeRamp]

    public init(
        asset: AVAsset,
        timeRange: CMTimeRange,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0,
        volume: Float = 1,
        audioRamps: [AudioVolumeRamp] = []
    ) {
        self.clipSource = AssetClipSource(asset: asset, sourceTimeRange: sourceTimeRange)
        self.asset = asset
        self.sourceTimeRange = sourceTimeRange
        self.volume = volume
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public convenience init?(
        recordedClip: RecordedClip,
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0,
        volume: Float? = nil,
        audioRamps: [AudioVolumeRamp] = []
    ) {
        guard let source = AssetClipSource(recordedClip: recordedClip, sourceTimeRange: sourceTimeRange) else {
            return nil
        }
        let effectiveDuration = sourceTimeRange?.duration ?? recordedClip.duration
        self.init(
            source: source,
            timeRange: CMTimeRange(start: startTime, duration: effectiveDuration),
            layerLevel: layerLevel,
            volume: volume ?? (recordedClip.isMutedOnMerge ? 0 : 1),
            audioRamps: audioRamps
        )
    }

    public init(
        source: AssetClipSource,
        timeRange: CMTimeRange,
        layerLevel: Int = 0,
        volume: Float = 1,
        audioRamps: [AudioVolumeRamp] = []
    ) {
        self.clipSource = source
        self.asset = source.asset
        self.sourceTimeRange = source.sourceTimeRange
        self.volume = volume
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange, layerLevel: layerLevel)
        self.transform = source.preferredTransform
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = ClipLayer(
            source: clipSource,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            layerLevel: layerLevel + inheritedLevel,
            volume: volume,
            audioRamps: audioRamps.map { $0.applyingOffset(offset) }
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }
}

public final class ImageLayer: TimelineLayer {
    public let imageSource: StillImageSource
    public let image: CGImage

    public init(image: CGImage, timeRange: CMTimeRange, layerLevel: Int = 0) {
        self.imageSource = StillImageSource(image: image)
        self.image = image
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public init(source: StillImageSource, timeRange: CMTimeRange, layerLevel: Int = 0) {
        self.imageSource = source
        self.image = source.image
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = ImageLayer(
            source: imageSource,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            layerLevel: layerLevel + inheritedLevel
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }
}

public enum TimelineTextAnimationStyle: Equatable {
    case none
    case opacity
}

public final class TextLayer: TimelineLayer {
    public let attributedText: NSAttributedString
    public var frame: CGRect
    public var animationStyle: TimelineTextAnimationStyle
    public var contentsScale: CGFloat
    public var cornerRadius: CGFloat
    public var masksToBounds: Bool
    public var backgroundColor: CGColor?
    public var alignmentMode: CATextLayerAlignmentMode

    public init(
        attributedText: NSAttributedString,
        frame: CGRect,
        timeRange: CMTimeRange,
        layerLevel: Int = 0,
        animationStyle: TimelineTextAnimationStyle = .none,
        contentsScale: CGFloat = 2,
        cornerRadius: CGFloat = 0,
        masksToBounds: Bool = false,
        backgroundColor: CGColor? = nil,
        alignmentMode: CATextLayerAlignmentMode = .left
    ) {
        self.attributedText = attributedText
        self.frame = frame
        self.animationStyle = animationStyle
        self.contentsScale = contentsScale
        self.cornerRadius = cornerRadius
        self.masksToBounds = masksToBounds
        self.backgroundColor = backgroundColor
        self.alignmentMode = alignmentMode
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = TextLayer(
            attributedText: attributedText,
            frame: frame,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            layerLevel: layerLevel + inheritedLevel,
            animationStyle: animationStyle,
            contentsScale: contentsScale,
            cornerRadius: cornerRadius,
            masksToBounds: masksToBounds,
            backgroundColor: backgroundColor,
            alignmentMode: alignmentMode
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }

    func makePresentationLayer(duration: CFTimeInterval) -> CALayer {
        #if canImport(UIKit)
        let container: CALayer
        switch animationStyle {
        case .none:
            let textLayer = CATextLayer()
            textLayer.string = attributedText
            textLayer.alignmentMode = alignmentMode
            textLayer.contentsScale = contentsScale
            textLayer.isWrapped = true
            textLayer.frame = boundsForPresentation()
            container = textLayer
        case .opacity:
            let textLayer = TimelineTextOpacityAnimationLayer()
            textLayer.attributedText = attributedText
            textLayer.frame = boundsForPresentation()
            container = textLayer
        }
        #else
        let textLayer = CATextLayer()
        textLayer.string = attributedText
        textLayer.alignmentMode = alignmentMode
        textLayer.contentsScale = contentsScale
        textLayer.isWrapped = true
        textLayer.frame = boundsForPresentation()
        let container: CALayer = textLayer
        #endif

        container.opacity = opacity
        container.backgroundColor = backgroundColor
        container.cornerRadius = cornerRadius
        container.masksToBounds = masksToBounds
        container.anchorPoint = .zero
        container.position = frame.origin
        container.setAffineTransform(transform)

        let beginTime = AVCoreAnimationBeginTimeAtZero + timeRange.start.seconds
        let endTime = beginTime + timeRange.duration.seconds
        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.keyTimes = [0, NSNumber(value: beginTime / max(duration, 0.0001)), NSNumber(value: endTime / max(duration, 0.0001)), 1]
        visibility.values = [0, opacity, opacity, 0]
        visibility.duration = duration
        visibility.beginTime = AVCoreAnimationBeginTimeAtZero
        visibility.fillMode = .both
        visibility.isRemovedOnCompletion = false
        container.add(visibility, forKey: "timelineVisibility")
        return container
    }

    private func boundsForPresentation() -> CGRect {
        CGRect(origin: .zero, size: frame.size)
    }
}

public final class AudioLayer: TimelineLayer {
    public let audioSource: AudioClipSource
    public let asset: AVAsset
    public var sourceTimeRange: CMTimeRange?
    public var volume: Float
    public var audioRamps: [AudioVolumeRamp]

    public init(
        asset: AVAsset,
        timeRange: CMTimeRange,
        sourceTimeRange: CMTimeRange? = nil,
        volume: Float = 1,
        audioRamps: [AudioVolumeRamp] = []
    ) {
        self.audioSource = AudioClipSource(asset: asset, sourceTimeRange: sourceTimeRange)
        self.asset = asset
        self.sourceTimeRange = sourceTimeRange
        self.volume = volume
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange)
    }

    public init(
        source: AudioClipSource,
        timeRange: CMTimeRange,
        volume: Float = 1,
        audioRamps: [AudioVolumeRamp] = []
    ) {
        self.audioSource = source
        self.asset = source.asset
        self.sourceTimeRange = source.sourceTimeRange
        self.volume = volume
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = AudioLayer(
            source: audioSource,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            volume: volume,
            audioRamps: audioRamps.map { $0.applyingOffset(offset) }
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        shifted.layerLevel = layerLevel + inheritedLevel
        return shifted
    }
}

public final class EffectLayer: TimelineLayer {
    public let effectSource: EffectSource
    public var processor: FrameProcessor?
    public var intensity: Float

    public init(timeRange: CMTimeRange, processor: FrameProcessor? = nil, intensity: Float = 1, layerLevel: Int = 0) {
        self.effectSource = EffectSource(processor: processor, intensity: intensity)
        self.processor = processor
        self.intensity = intensity
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public init(timeRange: CMTimeRange, source: EffectSource, layerLevel: Int = 0) {
        self.effectSource = source
        self.processor = source.processor
        self.intensity = source.intensity
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = EffectLayer(
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            source: effectSource,
            layerLevel: layerLevel + inheritedLevel
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }
}

public final class GroupLayer: TimelineLayer {
    public var layers: [TimelineLayer]

    public init(timeRange: CMTimeRange, layers: [TimelineLayer], layerLevel: Int = 0) {
        self.layers = layers
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shiftedChildren = layers.map { child in
            child.applyingOffset(offset + timeRange.start, inheritedLevel: layerLevel + inheritedLevel)
        }
        let shifted = GroupLayer(
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            layers: shiftedChildren,
            layerLevel: layerLevel + inheritedLevel
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }

    internal func flattenedLayers(
        offset: CMTime = .zero,
        inheritedLevel: Int = 0,
        inheritedState: TimelineLayerInheritance = .identity
    ) -> [TimelineLayer] {
        let shiftedStart = offset + timeRange.start
        let combinedState = inheritedState.appending(layer: self)

        return layers.flatMap { child -> [TimelineLayer] in
            if let group = child as? GroupLayer {
                return group.flattenedLayers(
                    offset: shiftedStart,
                    inheritedLevel: layerLevel + inheritedLevel,
                    inheritedState: combinedState
                )
            }

            let shifted = child.applyingOffset(shiftedStart, inheritedLevel: layerLevel + inheritedLevel)
            shifted.opacity *= combinedState.opacity
            shifted.transform = combinedState.transform.concatenating(shifted.transform)
            shifted.keyframes = combinedState.keyframes + shifted.keyframes
            return [shifted]
        }
    }
}

public struct AudioVolumeRamp {
    public var startVolume: Float
    public var endVolume: Float
    public var timeRange: CMTimeRange
    public var timingFunction: TimelineEasing

    public init(startVolume: Float, endVolume: Float, timeRange: CMTimeRange, easing: TimelineEasing = .linear) {
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timeRange = timeRange
        self.timingFunction = easing
    }

    public init(startVolume: Float, endVolume: Float, timeRange: CMTimeRange, timingFunction: TimelineEasing) {
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timeRange = timeRange
        self.timingFunction = timingFunction
    }

    public var easing: TimelineEasing {
        get { timingFunction }
        set { timingFunction = newValue }
    }

    public func applyingOffset(_ offset: CMTime) -> AudioVolumeRamp {
        AudioVolumeRamp(
            startVolume: startVolume,
            endVolume: endVolume,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            timingFunction: timingFunction
        )
    }
}
