//
//  TimelineRenderNode.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation
import CoreGraphics

internal struct TimelineRenderAudioConfiguration {
    var volume: Float
    var ramps: [AudioVolumeRamp]

    nonisolated(unsafe) static let identity = TimelineRenderAudioConfiguration(volume: 1, ramps: [])
}

internal struct TimelineRenderInheritanceState {
    var opacity: Float
    var transform: CGAffineTransform
    var keyframes: [KeyframeAnimation]

    nonisolated(unsafe) static let identity = TimelineRenderInheritanceState(
        opacity: 1,
        transform: .identity,
        keyframes: []
    )

    func appending(layer: TimelineLayer) -> TimelineRenderInheritanceState {
        TimelineRenderInheritanceState(
            opacity: opacity * layer.opacity,
            transform: transform.concatenating(layer.transform),
            keyframes: keyframes + layer.keyframes
        )
    }
}

internal class TimelineRenderLayerNode {
    let layer: TimelineLayer

    init(layer: TimelineLayer) {
        self.layer = layer
    }

    var timeRange: CMTimeRange { layer.timeRange }
    var layerLevel: Int { layer.layerLevel }
    var transform: CGAffineTransform { layer.transform }
    var opacity: Float { layer.opacity }
    var keyframes: [KeyframeAnimation] { layer.keyframes }

    var clipLayer: ClipLayer? { layer as? ClipLayer }
    var imageLayer: ImageLayer? { layer as? ImageLayer }
    var audioLayer: AudioLayer? { layer as? AudioLayer }
    var effectLayer: EffectLayer? { layer as? EffectLayer }
    var groupLayer: GroupLayer? { layer as? GroupLayer }

    var audioConfiguration: TimelineRenderAudioConfiguration {
        if let clipLayer {
            return TimelineRenderAudioConfiguration(volume: clipLayer.volume, ramps: clipLayer.audioRamps)
        }
        if let audioLayer {
            return TimelineRenderAudioConfiguration(volume: audioLayer.volume, ramps: audioLayer.audioRamps)
        }
        return .identity
    }
}

internal final class TimelineRenderGroupNode: TimelineRenderLayerNode {
    let children: [TimelineRenderLayerNode]

    init(groupLayer: GroupLayer, children: [TimelineRenderLayerNode]) {
        self.children = children
        super.init(layer: groupLayer)
    }

    func flattenedLayers(
        offset: CMTime = .zero,
        inheritedLevel: Int = 0,
        inheritedState: TimelineRenderInheritanceState = .identity
    ) -> [TimelineLayer] {
        guard let groupLayer else { return [] }
        let shiftedStart = offset + groupLayer.timeRange.start
        let combinedState = inheritedState.appending(layer: groupLayer)

        return children.flatMap { node -> [TimelineLayer] in
            if let groupNode = node as? TimelineRenderGroupNode {
                return groupNode.flattenedLayers(
                    offset: shiftedStart,
                    inheritedLevel: groupLayer.layerLevel + inheritedLevel,
                    inheritedState: combinedState
                )
            }

            let shifted = node.layer.applyingOffset(shiftedStart, inheritedLevel: groupLayer.layerLevel + inheritedLevel)
            shifted.opacity *= combinedState.opacity
            shifted.transform = combinedState.transform.concatenating(shifted.transform)
            shifted.keyframes = combinedState.keyframes + shifted.keyframes
            return [shifted]
        }
    }
}

internal struct TimelineVideoRenderLayerNode {
    let layer: ClipLayer
    let trackID: CMPersistentTrackID
    let preferredTransform: CGAffineTransform
    let timeRangeInTimeline: CMTimeRange
}

internal struct TimelineAudioRenderLayerNode {
    let layer: TimelineLayer
    let trackID: CMPersistentTrackID
    let timeRangeInTimeline: CMTimeRange
    let configuration: TimelineRenderAudioConfiguration
}

internal struct TimelineRenderCompositionNode {
    let renderSize: CGSize
    let frameDuration: CMTime
    let layerNodes: [TimelineRenderLayerNode]
    let transitions: [Transition]

    func flattenedLayers() -> [TimelineLayer] {
        layerNodes.flatMap { node -> [TimelineLayer] in
            if let groupNode = node as? TimelineRenderGroupNode {
                return groupNode.flattenedLayers()
            }
            return [node.layer]
        }
    }
}

internal enum TimelineRenderNodeBuilder {
    static func build(from composition: TimelineComposition) -> TimelineRenderCompositionNode {
        TimelineRenderCompositionNode(
            renderSize: composition.renderSize,
            frameDuration: composition.frameDuration,
            layerNodes: composition.layers.map(makeNode),
            transitions: composition.transitions
        )
    }

    private static func makeNode(from layer: TimelineLayer) -> TimelineRenderLayerNode {
        if let groupLayer = layer as? GroupLayer {
            let children = groupLayer.layers.map(makeNode)
            return TimelineRenderGroupNode(groupLayer: groupLayer, children: children)
        }
        return TimelineRenderLayerNode(layer: layer)
    }
}
