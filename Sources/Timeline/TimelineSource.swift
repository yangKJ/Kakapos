//
//  TimelineSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics

public enum TimelineSourceKind: Equatable {
    case assetClip
    case stillImage
    case text
    case audioClip
    case effect
}

public protocol TimelineSourceDescriptor {
    var kind: TimelineSourceKind { get }
    var nominalDuration: CMTime? { get }
}

public struct AssetClipSource: TimelineSourceDescriptor {
    public let asset: AVAsset
    public let trackID: CMPersistentTrackID?
    public let sourceTimeRange: CMTimeRange?
    public let preferredTransform: CGAffineTransform

    public var kind: TimelineSourceKind { .assetClip }
    public var nominalDuration: CMTime? { sourceTimeRange?.duration ?? asset.duration }

    public init(
        asset: AVAsset,
        trackID: CMPersistentTrackID? = nil,
        sourceTimeRange: CMTimeRange? = nil,
        preferredTransform: CGAffineTransform? = nil
    ) {
        self.asset = asset
        self.trackID = trackID
        self.sourceTimeRange = sourceTimeRange
        self.preferredTransform = preferredTransform
            ?? asset.tracks(withMediaType: .video).first?.preferredTransform
            ?? .identity
    }
}

public struct AudioClipSource: TimelineSourceDescriptor {
    public let asset: AVAsset
    public let trackID: CMPersistentTrackID?
    public let sourceTimeRange: CMTimeRange?

    public var kind: TimelineSourceKind { .audioClip }
    public var nominalDuration: CMTime? { sourceTimeRange?.duration ?? asset.duration }

    public init(
        asset: AVAsset,
        trackID: CMPersistentTrackID? = nil,
        sourceTimeRange: CMTimeRange? = nil
    ) {
        self.asset = asset
        self.trackID = trackID
        self.sourceTimeRange = sourceTimeRange
    }
}

public struct StillImageSource: TimelineSourceDescriptor {
    public let image: CGImage
    public let nominalFrameDuration: CMTime
    public let naturalSize: CGSize

    public var kind: TimelineSourceKind { .stillImage }
    public var nominalDuration: CMTime? { nominalFrameDuration }

    public init(
        image: CGImage,
        nominalFrameDuration: CMTime = CMTime(value: 1, timescale: 30)
    ) {
        self.image = image
        self.nominalFrameDuration = nominalFrameDuration
        self.naturalSize = CGSize(width: image.width, height: image.height)
    }
}

public struct EffectSource: TimelineSourceDescriptor {
    public let processor: FrameProcessor?
    public let intensity: Float

    public var kind: TimelineSourceKind { .effect }
    public var nominalDuration: CMTime? { nil }

    public init(processor: FrameProcessor?, intensity: Float = 1) {
        self.processor = processor
        self.intensity = intensity
    }
}

public struct TextClipSource: TimelineSourceDescriptor {
    public let attributedText: NSAttributedString
    public let frame: CGRect
    public let animationStyle: TimelineTextAnimationStyle

    public var kind: TimelineSourceKind { .text }
    public var nominalDuration: CMTime? { nil }

    public init(
        attributedText: NSAttributedString,
        frame: CGRect,
        animationStyle: TimelineTextAnimationStyle = .none
    ) {
        self.attributedText = attributedText
        self.frame = frame
        self.animationStyle = animationStyle
    }
}

public struct TimelineAssetSegment {
    public var source: AssetClipSource
    public var destinationTimeRange: CMTimeRange
    public var compositionTrackID: CMPersistentTrackID?
    public var layerLevel: Int
    public var opacity: Float
    public var transform: CGAffineTransform

    public init(
        source: AssetClipSource,
        destinationTimeRange: CMTimeRange,
        compositionTrackID: CMPersistentTrackID?,
        layerLevel: Int,
        opacity: Float,
        transform: CGAffineTransform
    ) {
        self.source = source
        self.destinationTimeRange = destinationTimeRange
        self.compositionTrackID = compositionTrackID
        self.layerLevel = layerLevel
        self.opacity = opacity
        self.transform = transform
    }
}

public struct TimelineAudioSegment {
    public var source: AudioClipSource
    public var destinationTimeRange: CMTimeRange
    public var compositionTrackID: CMPersistentTrackID?
    public var layerLevel: Int
    public var volume: Float
    public var ramps: [AudioVolumeRamp]

    public init(
        source: AudioClipSource,
        destinationTimeRange: CMTimeRange,
        compositionTrackID: CMPersistentTrackID?,
        layerLevel: Int,
        volume: Float,
        ramps: [AudioVolumeRamp]
    ) {
        self.source = source
        self.destinationTimeRange = destinationTimeRange
        self.compositionTrackID = compositionTrackID
        self.layerLevel = layerLevel
        self.volume = volume
        self.ramps = ramps
    }
}

public struct TimelineImageSegment {
    public var source: StillImageSource
    public var destinationTimeRange: CMTimeRange
    public var layerLevel: Int
    public var opacity: Float
    public var transform: CGAffineTransform

    public init(
        source: StillImageSource,
        destinationTimeRange: CMTimeRange,
        layerLevel: Int,
        opacity: Float,
        transform: CGAffineTransform
    ) {
        self.source = source
        self.destinationTimeRange = destinationTimeRange
        self.layerLevel = layerLevel
        self.opacity = opacity
        self.transform = transform
    }
}

public struct TimelineTextSegment {
    public var source: TextClipSource
    public var destinationTimeRange: CMTimeRange
    public var layerLevel: Int
    public var opacity: Float
    public var transform: CGAffineTransform

    public init(
        source: TextClipSource,
        destinationTimeRange: CMTimeRange,
        layerLevel: Int,
        opacity: Float,
        transform: CGAffineTransform
    ) {
        self.source = source
        self.destinationTimeRange = destinationTimeRange
        self.layerLevel = layerLevel
        self.opacity = opacity
        self.transform = transform
    }
}

public struct TimelineProcessorSegment {
    public var source: EffectSource
    public var destinationTimeRange: CMTimeRange
    public var layerLevel: Int
    public var keyframes: [KeyframeAnimation]

    public init(
        source: EffectSource,
        destinationTimeRange: CMTimeRange,
        layerLevel: Int,
        keyframes: [KeyframeAnimation]
    ) {
        self.source = source
        self.destinationTimeRange = destinationTimeRange
        self.layerLevel = layerLevel
        self.keyframes = keyframes
    }

    public func intensity(at time: CMTime) -> Float {
        KeyframeAnimation.value(for: "effect.intensity", at: time, animations: keyframes)
            ?? KeyframeAnimation.value(for: "intensity", at: time, animations: keyframes)
            ?? source.intensity
    }
}

public struct TimelineRenderPlan {
    public struct VisualInterval {
        public var timeRange: CMTimeRange
        public var assetSegments: [TimelineAssetSegment]
        public var imageSegments: [TimelineImageSegment]
        public var textSegments: [TimelineTextSegment]
        public var processorSegments: [TimelineProcessorSegment]

        public init(
            timeRange: CMTimeRange,
            assetSegments: [TimelineAssetSegment],
            imageSegments: [TimelineImageSegment],
            textSegments: [TimelineTextSegment],
            processorSegments: [TimelineProcessorSegment]
        ) {
            self.timeRange = timeRange
            self.assetSegments = assetSegments
            self.imageSegments = imageSegments
            self.textSegments = textSegments
            self.processorSegments = processorSegments
        }
    }

    public var assetSegments: [TimelineAssetSegment]
    public var audioSegments: [TimelineAudioSegment]
    public var imageSegments: [TimelineImageSegment]
    public var textSegments: [TimelineTextSegment]
    public var processorSegments: [TimelineProcessorSegment]
    public var transitions: [Transition]
    public var visualIntervals: [VisualInterval]

    public init(
        assetSegments: [TimelineAssetSegment],
        audioSegments: [TimelineAudioSegment],
        imageSegments: [TimelineImageSegment],
        textSegments: [TimelineTextSegment],
        processorSegments: [TimelineProcessorSegment],
        transitions: [Transition],
        visualIntervals: [VisualInterval]
    ) {
        self.assetSegments = assetSegments
        self.audioSegments = audioSegments
        self.imageSegments = imageSegments
        self.textSegments = textSegments
        self.processorSegments = processorSegments
        self.transitions = transitions
        self.visualIntervals = visualIntervals
    }
}

struct TimelineRenderPlanBuilder {
    let transitions: [Transition]

    func makePlan(
        renderInstructions: [TimelineRenderInstruction],
        resolvedLayers: ResolvedTimelineLayers,
        videoAllocation: [ObjectIdentifier: CMPersistentTrackID],
        audioAllocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> TimelineRenderPlan {
        let assetSegments = resolvedLayers.videoLayers.map { layer in
            TimelineAssetSegment(
                source: layer.clipSource,
                destinationTimeRange: layer.timeRange,
                compositionTrackID: videoAllocation[ObjectIdentifier(layer)],
                layerLevel: layer.layerLevel,
                opacity: layer.opacity,
                transform: layer.transform
            )
        }

        let audioSegments = resolvedLayers.videoLayers.map { layer in
            TimelineAudioSegment(
                source: AudioClipSource(
                    asset: layer.asset,
                    sourceTimeRange: layer.sourceTimeRange
                ),
                destinationTimeRange: layer.timeRange,
                compositionTrackID: audioAllocation[ObjectIdentifier(layer)],
                layerLevel: layer.layerLevel,
                volume: layer.volume,
                ramps: layer.audioRamps
            )
        } + resolvedLayers.audioLayers.map { layer in
            TimelineAudioSegment(
                source: layer.audioSource,
                destinationTimeRange: layer.timeRange,
                compositionTrackID: audioAllocation[ObjectIdentifier(layer)],
                layerLevel: layer.layerLevel,
                volume: layer.volume,
                ramps: layer.audioRamps
            )
        }

        let imageSegments = resolvedLayers.imageLayers.map { layer in
            TimelineImageSegment(
                source: layer.imageSource,
                destinationTimeRange: layer.timeRange,
                layerLevel: layer.layerLevel,
                opacity: layer.opacity,
                transform: layer.transform
            )
        }

        let textSegments = resolvedLayers.textLayers.map { layer in
            TimelineTextSegment(
                source: TextClipSource(
                    attributedText: layer.attributedText,
                    frame: layer.frame,
                    animationStyle: layer.animationStyle
                ),
                destinationTimeRange: layer.timeRange,
                layerLevel: layer.layerLevel,
                opacity: layer.opacity,
                transform: layer.transform
            )
        }

        let processorSegments = resolvedLayers.effectLayers.map { layer in
            TimelineProcessorSegment(
                source: layer.effectSource,
                destinationTimeRange: layer.timeRange,
                layerLevel: layer.layerLevel,
                keyframes: layer.keyframes
            )
        }

        let visualIntervals = renderInstructions.map { instruction in
            let assetSegmentsForInstruction = assetSegments
                .filter { $0.destinationTimeRange.start < instruction.timeRange.end && $0.destinationTimeRange.end > instruction.timeRange.start }
                .sorted { $0.layerLevel < $1.layerLevel }
            let imageSegmentsForInstruction = imageSegments
                .filter { $0.destinationTimeRange.start < instruction.timeRange.end && $0.destinationTimeRange.end > instruction.timeRange.start }
                .sorted { $0.layerLevel < $1.layerLevel }
            let textSegmentsForInstruction = textSegments
                .filter { $0.destinationTimeRange.start < instruction.timeRange.end && $0.destinationTimeRange.end > instruction.timeRange.start }
                .sorted { $0.layerLevel < $1.layerLevel }
            let processorSegmentsForInstruction = processorSegments
                .filter { $0.destinationTimeRange.start < instruction.timeRange.end && $0.destinationTimeRange.end > instruction.timeRange.start }
                .sorted { $0.layerLevel < $1.layerLevel }

            return TimelineRenderPlan.VisualInterval(
                timeRange: instruction.timeRange,
                assetSegments: assetSegmentsForInstruction,
                imageSegments: imageSegmentsForInstruction,
                textSegments: textSegmentsForInstruction,
                processorSegments: processorSegmentsForInstruction
            )
        }

        return TimelineRenderPlan(
            assetSegments: assetSegments,
            audioSegments: audioSegments,
            imageSegments: imageSegments,
            textSegments: textSegments,
            processorSegments: processorSegments,
            transitions: transitions,
            visualIntervals: visualIntervals
        )
    }
}

public extension CompiledTimelineComposition {
    func makeAssetSources(
        callbackQueue: DispatchQueue = .main,
        audioOutputSettings: [String: Any]? = nil
    ) -> [AssetSource] {
        renderPlan.assetSegments.map { segment in
            AssetSource(
                asset: segment.source.asset,
                timeRange: segment.source.sourceTimeRange,
                audioOutputSettings: audioOutputSettings,
                callbackQueue: callbackQueue
            )
        }
    }

    func makeImageSource(
        callbackQueue: DispatchQueue = .main
    ) -> ImageSource? {
        guard !renderPlan.imageSegments.isEmpty else { return nil }
        let frames = renderPlan.imageSegments
            .sorted { lhs, rhs in
                if lhs.destinationTimeRange.start == rhs.destinationTimeRange.start {
                    return lhs.layerLevel < rhs.layerLevel
                }
                return lhs.destinationTimeRange.start < rhs.destinationTimeRange.start
            }
            .map { segment in
                StillImageFrame(
                    image: segment.source.image,
                    duration: segment.destinationTimeRange.duration,
                    transform: segment.transform,
                    userInfo: [
                        "kakapos.timeline.layer-level": segment.layerLevel,
                        "kakapos.timeline.opacity": segment.opacity
                    ]
                )
            }
        return ImageSource(
            frames: frames,
            renderSize: videoComposition.renderSize,
            callbackQueue: callbackQueue
        )
    }

    func makeProcessorChain() -> MediaProcessorChain {
        let processors = renderPlan.processorSegments
            .sorted { lhs, rhs in
                if lhs.destinationTimeRange.start == rhs.destinationTimeRange.start {
                    return lhs.layerLevel < rhs.layerLevel
                }
                return lhs.destinationTimeRange.start < rhs.destinationTimeRange.start
            }
            .compactMap { $0.source.processor }
        return MediaProcessorChain(processors: processors, sinks: [])
    }
}
