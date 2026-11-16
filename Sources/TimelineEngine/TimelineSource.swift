//
//  TimelineSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation
import CoreGraphics

struct TimelineSourceSendableBox<T>: @unchecked Sendable {
    let value: T
}

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

    public init?(
        recordedClip: RecordedClip,
        sourceTimeRange: CMTimeRange? = nil,
        preferredTransform: CGAffineTransform? = nil
    ) {
        guard let asset = recordedClip.asset else {
            return nil
        }
        self.init(
            asset: asset,
            sourceTimeRange: sourceTimeRange,
            preferredTransform: preferredTransform
        )
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

    public init?(recordedClip: RecordedClip, sourceTimeRange: CMTimeRange? = nil) {
        guard let asset = recordedClip.asset else {
            return nil
        }
        self.init(asset: asset, sourceTimeRange: sourceTimeRange)
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
    let processorFactory: (() -> FrameProcessor)?

    public var kind: TimelineSourceKind { .effect }
    public var nominalDuration: CMTime? { nil }

    public init(processor: FrameProcessor?, intensity: Float = 1) {
        self.processor = processor
        self.intensity = intensity
        self.processorFactory = nil
    }

    public init(makeProcessor: @escaping () -> FrameProcessor, intensity: Float = 1) {
        self.processor = nil
        self.intensity = intensity
        self.processorFactory = makeProcessor
    }

    func makeProcessor() -> FrameProcessor? { processorFactory?() ?? processor }
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
    public var keyframes: [KeyframeAnimation] { didSet { keyframeIndex = TimelineKeyframeIndex(keyframes) } }
    private var keyframeIndex: TimelineKeyframeIndex

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
        self.keyframeIndex = TimelineKeyframeIndex(keyframes)
    }

    public func intensity(at time: CMTime) -> Float {
        keyframeIndex.value(for: "effect.intensity", at: time)
            ?? keyframeIndex.value(for: "intensity", at: time)
            ?? source.intensity
    }
}

public struct TimelineAudioMixSegment {
    public enum Kind {
        case layerRamp
        case transitionFadeIn
        case transitionFadeOut
    }

    public var kind: Kind
    public var compositionTrackID: CMPersistentTrackID?
    public var timeRange: CMTimeRange
    public var layerLevel: Int
    public var startVolume: Float
    public var endVolume: Float
    public var timingFunction: TimelineEasing

    public init(
        kind: Kind,
        compositionTrackID: CMPersistentTrackID?,
        timeRange: CMTimeRange,
        layerLevel: Int,
        startVolume: Float,
        endVolume: Float,
        timingFunction: TimelineEasing
    ) {
        self.kind = kind
        self.compositionTrackID = compositionTrackID
        self.timeRange = timeRange
        self.layerLevel = layerLevel
        self.startVolume = startVolume
        self.endVolume = endVolume
        self.timingFunction = timingFunction
    }
}

public struct TimelineTransitionSegment {
    public var transition: Transition
    public var timeRange: CMTimeRange
    public var sourceLayerLevel: Int?
    public var destinationLayerLevel: Int?
    public var sourceTrackID: CMPersistentTrackID?
    public var destinationTrackID: CMPersistentTrackID?

    public init(
        transition: Transition,
        timeRange: CMTimeRange,
        sourceLayerLevel: Int?,
        destinationLayerLevel: Int?,
        sourceTrackID: CMPersistentTrackID?,
        destinationTrackID: CMPersistentTrackID?
    ) {
        self.transition = transition
        self.timeRange = timeRange
        self.sourceLayerLevel = sourceLayerLevel
        self.destinationLayerLevel = destinationLayerLevel
        self.sourceTrackID = sourceTrackID
        self.destinationTrackID = destinationTrackID
    }
}

public struct TimelineRenderPlan {
    public struct VisualInterval {
        public var timeRange: CMTimeRange
        public var assetSegments: [TimelineAssetSegment]
        public var imageSegments: [TimelineImageSegment]
        public var textSegments: [TimelineTextSegment]
        public var processorSegments: [TimelineProcessorSegment]
        public var transitionSegments: [TimelineTransitionSegment]

        public init(
            timeRange: CMTimeRange,
            assetSegments: [TimelineAssetSegment],
            imageSegments: [TimelineImageSegment],
            textSegments: [TimelineTextSegment],
            processorSegments: [TimelineProcessorSegment],
            transitionSegments: [TimelineTransitionSegment]
        ) {
            self.timeRange = timeRange
            self.assetSegments = assetSegments
            self.imageSegments = imageSegments
            self.textSegments = textSegments
            self.processorSegments = processorSegments
            self.transitionSegments = transitionSegments
        }
    }

    public var assetSegments: [TimelineAssetSegment]
    public var audioSegments: [TimelineAudioSegment]
    public var imageSegments: [TimelineImageSegment]
    public var textSegments: [TimelineTextSegment]
    public var processorSegments: [TimelineProcessorSegment]
    public var transitions: [Transition]
    public var transitionSegments: [TimelineTransitionSegment]
    public var audioMixSegments: [TimelineAudioMixSegment]
    public var visualIntervals: [VisualInterval]

    public init(
        assetSegments: [TimelineAssetSegment],
        audioSegments: [TimelineAudioSegment],
        imageSegments: [TimelineImageSegment],
        textSegments: [TimelineTextSegment],
        processorSegments: [TimelineProcessorSegment],
        transitions: [Transition],
        transitionSegments: [TimelineTransitionSegment],
        audioMixSegments: [TimelineAudioMixSegment],
        visualIntervals: [VisualInterval]
    ) {
        self.assetSegments = assetSegments
        self.audioSegments = audioSegments
        self.imageSegments = imageSegments
        self.textSegments = textSegments
        self.processorSegments = processorSegments
        self.transitions = transitions
        self.transitionSegments = transitionSegments
        self.audioMixSegments = audioMixSegments
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

        let transitionSegments = makeTransitionSegments(
            transitions: transitions,
            assetSegments: assetSegments
        )
        let audioMixSegments = makeAudioMixSegments(
            audioSegments: audioSegments,
            transitionSegments: transitionSegments
        )

        var assets = TimelineIntervalIndex(assetSegments, range: { $0.destinationTimeRange }, level: { $0.layerLevel })
        var images = TimelineIntervalIndex(imageSegments, range: { $0.destinationTimeRange }, level: { $0.layerLevel })
        var texts = TimelineIntervalIndex(textSegments, range: { $0.destinationTimeRange }, level: { $0.layerLevel })
        var processors = TimelineIntervalIndex(processorSegments, range: { $0.destinationTimeRange }, level: { $0.layerLevel })
        var transitionIndex = TimelineIntervalIndex(transitionSegments, range: { $0.timeRange }, level: { _ in 0 })
        let visualIntervals = renderInstructions.map { instruction in
            TimelineRenderPlan.VisualInterval(
                timeRange: instruction.timeRange,
                assetSegments: assets.elements(overlapping: instruction.timeRange),
                imageSegments: images.elements(overlapping: instruction.timeRange),
                textSegments: texts.elements(overlapping: instruction.timeRange),
                processorSegments: processors.elements(overlapping: instruction.timeRange),
                transitionSegments: transitionIndex.elements(overlapping: instruction.timeRange)
            )
        }

        return TimelineRenderPlan(
            assetSegments: assetSegments,
            audioSegments: audioSegments,
            imageSegments: imageSegments,
            textSegments: textSegments,
            processorSegments: processorSegments,
            transitions: transitions,
            transitionSegments: transitionSegments,
            audioMixSegments: audioMixSegments,
            visualIntervals: visualIntervals
        )
    }

    private func makeTransitionSegments(
        transitions: [Transition],
        assetSegments: [TimelineAssetSegment]
    ) -> [TimelineTransitionSegment] {
        guard !transitions.isEmpty else { return [] }
        let orderedAssets = assetSegments.sorted {
            if $0.layerLevel == $1.layerLevel {
                return $0.destinationTimeRange.start < $1.destinationTimeRange.start
            }
            return $0.layerLevel < $1.layerLevel
        }
        return transitions.compactMap { transition in
            let candidates = orderedAssets
                .filter { $0.destinationTimeRange.start < transition.timeRange.end && $0.destinationTimeRange.end > transition.timeRange.start }

            guard candidates.count >= 2 else { return nil }

            let sourceSegment: TimelineAssetSegment?
            let destinationSegment: TimelineAssetSegment?
            if let sourceLevel = transition.sourceLayerLevel,
               let destinationLevel = transition.destinationLayerLevel {
                sourceSegment = candidates.first(where: { $0.layerLevel == sourceLevel })
                destinationSegment = candidates.first(where: { $0.layerLevel == destinationLevel })
            } else {
                sourceSegment = candidates.first
                destinationSegment = candidates.dropFirst().first
            }

            guard let sourceSegment, let destinationSegment else { return nil }
            let overlap = CMTimeRangeGetIntersection(transition.timeRange, otherRange: sourceSegment.destinationTimeRange)
            let transitionRange = CMTimeRangeGetIntersection(overlap, otherRange: destinationSegment.destinationTimeRange)
            guard transitionRange.isValid, !transitionRange.isEmpty else { return nil }

            return TimelineTransitionSegment(
                transition: transition,
                timeRange: transitionRange,
                sourceLayerLevel: sourceSegment.layerLevel,
                destinationLayerLevel: destinationSegment.layerLevel,
                sourceTrackID: sourceSegment.compositionTrackID,
                destinationTrackID: destinationSegment.compositionTrackID
            )
        }
    }

    private func makeAudioMixSegments(
        audioSegments: [TimelineAudioSegment],
        transitionSegments: [TimelineTransitionSegment]
    ) -> [TimelineAudioMixSegment] {
        let layerRampSegments = audioSegments.flatMap { segment in
            segment.ramps.flatMap { ramp -> [TimelineAudioMixSegment] in
                let range = CMTimeRangeGetIntersection(ramp.timeRange, otherRange: segment.destinationTimeRange)
                guard range.isValid, !range.isEmpty else { return [] }
                func value(_ time: CMTime) -> Float {
                    let fraction = ramp.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: ramp.timeRange))
                    return (ramp.startVolume + fraction * (ramp.endVolume - ramp.startVolume)) * segment.volume
                }
                if range == ramp.timeRange {
                    return [TimelineAudioMixSegment(kind: .layerRamp, compositionTrackID: segment.compositionTrackID,
                        timeRange: range, layerLevel: segment.layerLevel, startVolume: value(range.start),
                        endVolume: value(range.end), timingFunction: ramp.timingFunction)]
                }
                let times = TimelineCurveSampling.times(in: range, minimumStep: CMTime(value: 1, timescale: 48_000)) { [Double(value($0))] }
                return zip(times, times.dropFirst()).map { start, end in
                    TimelineAudioMixSegment(kind: .layerRamp, compositionTrackID: segment.compositionTrackID,
                        timeRange: CMTimeRange(start: start, end: end), layerLevel: segment.layerLevel,
                        startVolume: value(start), endVolume: value(end), timingFunction: .linear)
                }
            }
        }

        let transitionAudioSegments = transitionSegments.compactMap { transitionSegment -> [TimelineAudioMixSegment]? in
            guard transitionSegment.transition.audioBehavior == .crossfade,
                  let sourceLayerLevel = transitionSegment.sourceLayerLevel,
                  let destinationLayerLevel = transitionSegment.destinationLayerLevel,
                  let sourceSegment = audioSegments.first(where: {
                      $0.layerLevel == sourceLayerLevel &&
                      $0.destinationTimeRange.start < transitionSegment.timeRange.end &&
                      $0.destinationTimeRange.end > transitionSegment.timeRange.start
                  }),
                  let destinationSegment = audioSegments.first(where: {
                      $0.layerLevel == destinationLayerLevel &&
                      $0.destinationTimeRange.start < transitionSegment.timeRange.end &&
                      $0.destinationTimeRange.end > transitionSegment.timeRange.start
                  }) else {
                return nil
            }

            let range = transitionSegment.timeRange
            let transition = transitionSegment.transition
            return [(sourceSegment, TimelineAudioMixSegment.Kind.transitionFadeOut, false),
                (destinationSegment, TimelineAudioMixSegment.Kind.transitionFadeIn, true)].flatMap { segment, kind, fadesIn in
                func value(_ time: CMTime) -> Float {
                    let progress = transition.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: transition.timeRange))
                    return segment.volume * (fadesIn ? progress : 1 - progress)
                }
                if range == transition.timeRange {
                    return [TimelineAudioMixSegment(kind: kind, compositionTrackID: segment.compositionTrackID,
                        timeRange: range, layerLevel: segment.layerLevel, startVolume: value(range.start),
                        endVolume: value(range.end), timingFunction: transition.timingFunction)]
                }
                let times = TimelineCurveSampling.times(in: range, minimumStep: CMTime(value: 1, timescale: 48_000)) { [Double(value($0))] }
                return zip(times, times.dropFirst()).map { start, end in
                    TimelineAudioMixSegment(kind: kind, compositionTrackID: segment.compositionTrackID,
                        timeRange: CMTimeRange(start: start, end: end), layerLevel: segment.layerLevel,
                        startVolume: value(start), endVolume: value(end), timingFunction: .linear)
                }
            }
        }.flatMap { $0 }

        return (layerRampSegments + transitionAudioSegments).sorted {
            if $0.timeRange.start == $1.timeRange.start {
                return $0.layerLevel < $1.layerLevel
            }
            return $0.timeRange.start < $1.timeRange.start
        }
    }
}

public extension CompiledTimelineComposition {
    var timelineProcessors: [FrameProcessor] {
        renderPlan.processorSegments.enumerated()
            .sorted { lhs, rhs in
                lhs.element.layerLevel == rhs.element.layerLevel
                    ? lhs.offset < rhs.offset
                    : lhs.element.layerLevel < rhs.element.layerLevel
            }
            .compactMap { entry in
                guard let processor = entry.element.source.makeProcessor() else { return nil }
                return TimelineEffectProcessor(segment: entry.element, processor: processor)
            }
    }

    @MainActor
    func makePlayerItem() -> AVPlayerItem {
        let compositionBox = TimelineSourceSendableBox(value: composition)
        let playerItem = AVPlayerItem(asset: compositionBox.value)
        if exportProfile.colorPolicy.isHDR {
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = exportProfile.colorPolicy == .hdrHLG ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }
        playerItem.videoComposition = videoComposition
        playerItem.audioMix = audioMix
        return playerItem
    }

    func makeExportJob(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        videoFrameProcessingTimeout: TimeInterval? = nil
    ) -> ReaderWriterExportJob {
        let processors = videoProcessors.isEmpty ? timelineProcessors : videoProcessors
        return ReaderWriterExportJob(
            asset: composition,
            outputURL: outputURL,
            fileType: fileType,
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            videoComposition: videoComposition,
            audioMix: audioMix,
            videoProcessors: processors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout,
            exportProfile: exportProfile,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            preflightError: diagnostics.isEmpty
                ? nil
                : TimelineCompilationError.insertionFailed(diagnostics)
        )
    }

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
        MediaProcessorChain(processors: timelineProcessors, sinks: [])
    }
}
