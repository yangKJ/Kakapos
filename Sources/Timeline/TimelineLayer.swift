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
}

public final class ImageLayer: TimelineLayer {
    public let image: CGImage

    public init(image: CGImage, timeRange: CMTimeRange, layerLevel: Int = 0) {
        self.image = image
        super.init(timeRange: timeRange, layerLevel: layerLevel)
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
}

public final class EffectLayer: TimelineLayer {
    public var processor: FrameProcessor?
    public var intensity: Float

    public init(timeRange: CMTimeRange, processor: FrameProcessor? = nil, intensity: Float = 1, layerLevel: Int = 0) {
        self.processor = processor
        self.intensity = intensity
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }
}

public final class GroupLayer: TimelineLayer {
    public var layers: [TimelineLayer]

    public init(timeRange: CMTimeRange, layers: [TimelineLayer], layerLevel: Int = 0) {
        self.layers = layers
        super.init(timeRange: timeRange, layerLevel: layerLevel)
    }
}

public struct AudioVolumeRamp {
    public var startVolume: Float
    public var endVolume: Float
    public var timeRange: CMTimeRange

    public init(startVolume: Float, endVolume: Float, timeRange: CMTimeRange) {
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timeRange = timeRange
    }
}
