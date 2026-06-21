//
//  TimelineComposition.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics
import QuartzCore

public enum TimelineLayerKind: Equatable {
    case clip
    case image
    case text
    case effect
}

public struct TimelineLayerRenderState {
    public let kind: TimelineLayerKind
    public let layerLevel: Int
    public let opacity: Float
    public let transform: CGAffineTransform
    public let trackID: CMPersistentTrackID?
    public let image: CGImage?
    public let processor: FrameProcessor?
    public let effectIntensity: Float?
}

public struct TimelineRenderInstruction {
    public let timeRange: CMTimeRange
    public let layerLevels: [Int]
    public let sourceTrackIDs: [CMPersistentTrackID]
    public let layerStates: [TimelineLayerRenderState]
    public let processors: [FrameProcessor]
}

public struct ResolvedTimelineLayers {
    public let videoLayers: [ClipLayer]
    public let imageLayers: [ImageLayer]
    public let textLayers: [TextLayer]
    public let audioLayers: [AudioLayer]
    public let effectLayers: [EffectLayer]
}

public struct CompiledTimelineComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let renderInstructions: [TimelineRenderInstruction]
    public let resolvedLayers: ResolvedTimelineLayers
    public let renderPlan: TimelineRenderPlan
    public let overlayLayer: CALayer?
}

public struct TimelineCompilationSummary {
    public let renderSize: CGSize
    public let frameDuration: CMTime
    public let videoLayerCount: Int
    public let imageLayerCount: Int
    public let textLayerCount: Int
    public let effectLayerCount: Int
    public let transitionCount: Int
    public let visualIntervalCount: Int
    public let assetSegmentCount: Int
    public let audioSegmentCount: Int
    public let audioMixSegmentCount: Int
    public let videoTrackCount: Int
    public let audioTrackCount: Int
    public let sourceTrackIDCount: Int
    public let processorCount: Int

    public var summaryText: String {
        "video \(videoLayerCount) · image \(imageLayerCount) · text \(textLayerCount) · effect \(effectLayerCount) · transitions \(transitionCount) · tracks \(videoTrackCount)/\(audioTrackCount)"
    }
}

public final class TimelineComposition {
    public var renderSize: CGSize
    public var frameDuration: CMTime
    public var layers: [TimelineLayer]
    public var transitions: [Transition]

    public init(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = []
    ) {
        self.renderSize = renderSize
        self.frameDuration = frameDuration
        self.layers = layers
        self.transitions = transitions
    }

    public func addLayer(_ layer: TimelineLayer) {
        layers.append(layer)
    }

    public func addTransition(_ transition: Transition) {
        transitions.append(transition)
    }

    public func compile() -> CompiledTimelineComposition {
        TimelineCompiler(composition: self).compile()
    }
}

public extension CompiledTimelineComposition {
    var summary: TimelineCompilationSummary {
        let videoTrackIDs = Set(renderPlan.assetSegments.compactMap(\.compositionTrackID))
        let audioTrackIDs = Set(renderPlan.audioSegments.compactMap(\.compositionTrackID))
        return TimelineCompilationSummary(
            renderSize: videoComposition.renderSize,
            frameDuration: videoComposition.frameDuration,
            videoLayerCount: resolvedLayers.videoLayers.count,
            imageLayerCount: resolvedLayers.imageLayers.count,
            textLayerCount: resolvedLayers.textLayers.count,
            effectLayerCount: resolvedLayers.effectLayers.count,
            transitionCount: renderPlan.transitions.count,
            visualIntervalCount: renderPlan.visualIntervals.count,
            assetSegmentCount: renderPlan.assetSegments.count,
            audioSegmentCount: renderPlan.audioSegments.count,
            audioMixSegmentCount: renderPlan.audioMixSegments.count,
            videoTrackCount: composition.tracks(withMediaType: .video).count,
            audioTrackCount: composition.tracks(withMediaType: .audio).count,
            sourceTrackIDCount: videoTrackIDs.count + audioTrackIDs.count,
            processorCount: renderPlan.processorSegments.count
        )
    }
}
