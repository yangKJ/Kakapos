//
//  TimelineLayer.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics

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
    public var easing: TimelineEasing

    public init(startVolume: Float, endVolume: Float, timeRange: CMTimeRange, easing: TimelineEasing = .linear) {
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timeRange = timeRange
        self.easing = easing
    }

    public func applyingOffset(_ offset: CMTime) -> AudioVolumeRamp {
        AudioVolumeRamp(
            startVolume: startVolume,
            endVolume: endVolume,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            easing: easing
        )
    }
}
