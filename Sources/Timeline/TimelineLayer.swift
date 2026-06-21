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

public final class ClipLayer: TimelineLayer {
    public let asset: AVAsset
    public var sourceTimeRange: CMTimeRange?
    public var audioRamps: [AudioVolumeRamp]

    public init(asset: AVAsset, timeRange: CMTimeRange, sourceTimeRange: CMTimeRange? = nil, layerLevel: Int = 0, audioRamps: [AudioVolumeRamp] = []) {
        self.asset = asset
        self.sourceTimeRange = sourceTimeRange
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel + inheritedLevel,
            audioRamps: audioRamps.map { $0.applyingOffset(offset) }
        )
        shifted.opacity = opacity
        shifted.transform = transform
        shifted.keyframes = keyframes
        return shifted
    }
}

public final class ImageLayer: TimelineLayer {
    public let image: CGImage

    public init(image: CGImage, timeRange: CMTimeRange, layerLevel: Int = 0) {
        self.image = image
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = ImageLayer(
            image: image,
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
    public let asset: AVAsset
    public var sourceTimeRange: CMTimeRange?
    public var audioRamps: [AudioVolumeRamp]

    public init(asset: AVAsset, timeRange: CMTimeRange, sourceTimeRange: CMTimeRange? = nil, audioRamps: [AudioVolumeRamp] = []) {
        self.asset = asset
        self.sourceTimeRange = sourceTimeRange
        self.audioRamps = audioRamps
        super.init(timeRange: timeRange)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = AudioLayer(
            asset: asset,
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            sourceTimeRange: sourceTimeRange,
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
    public var processor: FrameProcessor?
    public var intensity: Float

    public init(timeRange: CMTimeRange, processor: FrameProcessor? = nil, intensity: Float = 1, layerLevel: Int = 0) {
        self.processor = processor
        self.intensity = intensity
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }

    public override func applyingOffset(_ offset: CMTime, inheritedLevel: Int = 0) -> TimelineLayer {
        let shifted = EffectLayer(
            timeRange: CMTimeRange(start: timeRange.start + offset, duration: timeRange.duration),
            processor: processor,
            intensity: intensity,
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
        let shiftedChildren = layers.map { $0.applyingOffset(offset + timeRange.start, inheritedLevel: layerLevel + inheritedLevel) }
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
