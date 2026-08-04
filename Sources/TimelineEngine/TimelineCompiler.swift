//
//  TimelineCompiler.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation
import CoreGraphics
import QuartzCore

internal final class TimelineCompiler {
    private let compositionModel: TimelineRenderCompositionNode

    init(composition: TimelineComposition) {
        self.compositionModel = TimelineRenderNodeBuilder.build(from: composition)
    }

    func compile() -> CompiledTimelineComposition {
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = compositionModel.renderSize
        videoComposition.frameDuration = compositionModel.frameDuration
        let audioMix = AVMutableAudioMix()

        let flattenedLayers = compositionModel.flattenedLayers()
        let resolvedLayers = resolve(flattenedLayers)

        let videoAllocation = allocateClipTracks(for: resolvedLayers.videoLayers)
        let audioAllocation = allocateAudioTracks(
            clipLayers: resolvedLayers.videoLayers,
            audioLayers: resolvedLayers.audioLayers
        )

        insertVideoLayers(resolvedLayers.videoLayers, allocation: videoAllocation, into: composition)
        let audioParameters = insertAudioLayers(
            clipLayers: resolvedLayers.videoLayers,
            audioLayers: resolvedLayers.audioLayers,
            allocation: audioAllocation,
            into: composition
        )

        let renderInstructions = buildRenderInstructions(
            videoLayers: resolvedLayers.videoLayers,
            imageLayers: resolvedLayers.imageLayers,
            textLayers: resolvedLayers.textLayers,
            effectLayers: resolvedLayers.effectLayers,
            allocation: videoAllocation
        )
        videoComposition.instructions = makeVideoInstructions(
            from: renderInstructions,
            composition: composition,
            videoLayers: resolvedLayers.videoLayers,
            allocation: videoAllocation
        )
        audioMix.inputParameters = audioParameters
        let renderPlan = TimelineRenderPlanBuilder(transitions: compositionModel.transitions).makePlan(
            renderInstructions: renderInstructions,
            resolvedLayers: resolvedLayers,
            videoAllocation: videoAllocation,
            audioAllocation: audioAllocation
        )
        let overlayLayer = makeOverlayLayer(
            textLayers: resolvedLayers.textLayers,
            renderSize: compositionModel.renderSize
        )
        if let overlayLayer, !resolvedLayers.videoLayers.isEmpty {
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: compositionModel.renderSize)
            let parentLayer = CALayer()
            parentLayer.frame = videoLayer.frame
            parentLayer.addSublayer(videoLayer)
            parentLayer.addSublayer(overlayLayer)
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        return CompiledTimelineComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            renderInstructions: renderInstructions,
            resolvedLayers: resolvedLayers,
            renderPlan: renderPlan,
            overlayLayer: overlayLayer
        )
    }

    private func resolve(_ layers: [TimelineLayer]) -> ResolvedTimelineLayers {
        let sortedLayers = layers.sorted {
            if $0.timeRange.start == $1.timeRange.start {
                return $0.layerLevel < $1.layerLevel
            }
            return $0.timeRange.start < $1.timeRange.start
        }
        return ResolvedTimelineLayers(
            videoLayers: sortedLayers.compactMap { $0 as? ClipLayer },
            imageLayers: sortedLayers.compactMap { $0 as? ImageLayer },
            textLayers: sortedLayers.compactMap { $0 as? TextLayer },
            audioLayers: sortedLayers.compactMap { $0 as? AudioLayer },
            effectLayers: sortedLayers.compactMap { $0 as? EffectLayer }
        )
    }

    private func allocateClipTracks(for layers: [ClipLayer]) -> [ObjectIdentifier: CMPersistentTrackID] {
        var assignments: [ObjectIdentifier: CMPersistentTrackID] = [:]
        var trackEndTimes: [CMPersistentTrackID: CMTime] = [:]
        var nextTrackID: CMPersistentTrackID = 1

        for layer in layers.sorted(by: { $0.timeRange.start < $1.timeRange.start }) {
            let identifier = ObjectIdentifier(layer)
            if let reusable = reusableTrack(for: layer.timeRange.start, trackEndTimes: trackEndTimes) {
                assignments[identifier] = reusable
                trackEndTimes[reusable] = layer.timeRange.end
                continue
            }
            let trackID = nextTrackID
            nextTrackID += 1
            assignments[identifier] = trackID
            trackEndTimes[trackID] = layer.timeRange.end
        }

        return assignments
    }

    private func allocateAudioTracks(
        clipLayers: [ClipLayer],
        audioLayers: [AudioLayer]
    ) -> [ObjectIdentifier: CMPersistentTrackID] {
        var assignments: [ObjectIdentifier: CMPersistentTrackID] = [:]
        var trackEndTimes: [CMPersistentTrackID: CMTime] = [:]
        var nextTrackID: CMPersistentTrackID = 10_000

        let entries = (clipLayers as [TimelineLayer] + audioLayers as [TimelineLayer]).sorted {
            if $0.timeRange.start == $1.timeRange.start {
                return $0.layerLevel < $1.layerLevel
            }
            return $0.timeRange.start < $1.timeRange.start
        }

        for entry in entries {
            let identifier = ObjectIdentifier(entry)
            if let reusable = reusableTrack(for: entry.timeRange.start, trackEndTimes: trackEndTimes) {
                assignments[identifier] = reusable
                trackEndTimes[reusable] = entry.timeRange.end
                continue
            }
            let trackID = nextTrackID
            nextTrackID += 1
            assignments[identifier] = trackID
            trackEndTimes[trackID] = entry.timeRange.end
        }

        return assignments
    }

    private func reusableTrack(
        for start: CMTime,
        trackEndTimes: [CMPersistentTrackID: CMTime]
    ) -> CMPersistentTrackID? {
        trackEndTimes
            .sorted { $0.value < $1.value }
            .first(where: { $0.value <= start })?
            .key
    }

    private func insertVideoLayers(
        _ layers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        into composition: AVMutableComposition
    ) {
        for layer in layers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .video).first else { continue }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .video,
                    preferredTrackID: trackID
                  ) else {
                continue
            }

            try? compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
            compositionTrack.preferredTransform = sourceTrack.preferredTransform
        }
    }

    private func insertAudioLayers(
        clipLayers: [ClipLayer],
        audioLayers: [AudioLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        into composition: AVMutableComposition
    ) -> [AVMutableAudioMixInputParameters] {
        var parametersByTrackID: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        for layer in clipLayers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .audio).first else { continue }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .audio,
                    preferredTrackID: trackID
                  ) else {
                continue
            }

            try? compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
            let parameters = parametersByTrackID[trackID] ?? AVMutableAudioMixInputParameters(track: compositionTrack)
            applyClipAudioMix(layer, to: parameters)
            parametersByTrackID[trackID] = parameters
        }

        for layer in audioLayers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .audio).first else { continue }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .audio,
                    preferredTrackID: trackID
                  ) else {
                continue
            }

            try? compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
            let parameters = parametersByTrackID[trackID] ?? AVMutableAudioMixInputParameters(track: compositionTrack)
            applyAudioLayerMix(layer, to: parameters)
            parametersByTrackID[trackID] = parameters
        }

        applyTransitionAudioMix(
            clipLayers: clipLayers,
            allocation: allocation,
            parametersByTrackID: &parametersByTrackID
        )

        return parametersByTrackID.keys.sorted().compactMap { parametersByTrackID[$0] }
    }

    private func applyClipAudioMix(_ layer: ClipLayer, to parameters: AVMutableAudioMixInputParameters) {
        parameters.setVolume(layer.volume, at: layer.timeRange.start)
        parameters.setVolume(layer.volume, at: layer.timeRange.end)
        applyAudioRamps(layer.audioRamps, baseVolume: layer.volume, allowedTimeRange: layer.timeRange, to: parameters)
    }

    private func applyAudioLayerMix(_ layer: AudioLayer, to parameters: AVMutableAudioMixInputParameters) {
        parameters.setVolume(layer.volume, at: layer.timeRange.start)
        parameters.setVolume(layer.volume, at: layer.timeRange.end)
        applyAudioRamps(layer.audioRamps, baseVolume: layer.volume, allowedTimeRange: layer.timeRange, to: parameters)
    }

    private func applyAudioRamps(
        _ ramps: [AudioVolumeRamp],
        baseVolume: Float,
        allowedTimeRange: CMTimeRange,
        to parameters: AVMutableAudioMixInputParameters
    ) {
        for ramp in ramps {
            let clippedRange = CMTimeRangeGetIntersection(ramp.timeRange, otherRange: allowedTimeRange)
            guard clippedRange.isValid, !clippedRange.isEmpty else { continue }
            parameters.setVolumeRamp(
                fromStartVolume: ramp.startVolume * baseVolume,
                toEndVolume: ramp.endVolume * baseVolume,
                timeRange: clippedRange
            )
        }
    }

    private func applyTransitionAudioMix(
        clipLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        parametersByTrackID: inout [CMPersistentTrackID: AVMutableAudioMixInputParameters]
    ) {
        guard !compositionModel.transitions.isEmpty else { return }
        let layerByTrackID = Dictionary(
            uniqueKeysWithValues: clipLayers.compactMap { layer -> (CMPersistentTrackID, (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState))? in
                guard let trackID = allocation[ObjectIdentifier(layer)] else { return nil }
                let startState = renderState(for: layer, at: layer.timeRange.start, allocation: allocation)
                let endState = renderState(for: layer, at: layer.timeRange.end, allocation: allocation)
                return (trackID, (layer, startState, endState))
            }
        )

        for transition in compositionModel.transitions where transition.kind == .crossDissolve && transition.audioBehavior == .crossfade {
            guard let selectedLayers = layersForTransition(transition, activeLayers: layerByTrackID) else { continue }
            let overlap = CMTimeRangeGetIntersection(transition.timeRange, otherRange: selectedLayers.source.layer.timeRange)
            let transitionRange = CMTimeRangeGetIntersection(overlap, otherRange: selectedLayers.destination.layer.timeRange)
            guard transitionRange.isValid, !transitionRange.isEmpty else { continue }

            if let sourceParameters = parametersByTrackID[selectedLayers.sourceTrackID] {
                sourceParameters.setVolumeRamp(
                    fromStartVolume: selectedLayers.source.layer.volume,
                    toEndVolume: 0,
                    timeRange: transitionRange
                )
            }

            if let destinationParameters = parametersByTrackID[selectedLayers.destinationTrackID] {
                destinationParameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: selectedLayers.destination.layer.volume,
                    timeRange: transitionRange
                )
            }
        }
    }

    private func buildRenderInstructions(
        videoLayers: [ClipLayer],
        imageLayers: [ImageLayer],
        textLayers: [TextLayer],
        effectLayers: [EffectLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [TimelineRenderInstruction] {
        let visualLayers = (videoLayers as [TimelineLayer]) + imageLayers + textLayers + effectLayers
        let activeLayers = visualLayers.filter { !$0.timeRange.isEmpty }
        let cutPoints = uniqueSortedTimes(activeLayers.flatMap { [$0.timeRange.start, $0.timeRange.end] })
        guard cutPoints.count >= 2 else { return [] }

        var instructions: [TimelineRenderInstruction] = []

        for index in 0..<(cutPoints.count - 1) {
            let start = cutPoints[index]
            let end = cutPoints[index + 1]
            let timeRange = CMTimeRange(start: start, end: end)
            let intervalLayers = activeLayers
                .filter { $0.timeRange.start < end && $0.timeRange.end > start }
                .sorted { $0.layerLevel < $1.layerLevel }

            guard !intervalLayers.isEmpty else { continue }

            let trackIDs = intervalLayers.compactMap { layer -> CMPersistentTrackID? in
                guard let clipLayer = layer as? ClipLayer else { return nil }
                return allocation[ObjectIdentifier(clipLayer)]
            }

            instructions.append(
                TimelineRenderInstruction(
                    timeRange: timeRange,
                    layerLevels: intervalLayers.map(\.layerLevel),
                    sourceTrackIDs: uniqueTrackIDsPreservingOrder(trackIDs),
                    layerStates: intervalLayers.map { renderState(for: $0, at: timeRange.start, allocation: allocation) },
                    processors: intervalLayers.compactMap { ($0 as? EffectLayer)?.processor }
                )
            )
        }

        return instructions
    }

    private func makeVideoInstructions(
        from renderInstructions: [TimelineRenderInstruction],
        composition: AVMutableComposition,
        videoLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [AVVideoCompositionInstructionProtocol] {
        renderInstructions.compactMap { instruction in
            let mutableInstruction = AVMutableVideoCompositionInstruction()
            mutableInstruction.timeRange = instruction.timeRange
            let activeClipLayers = activeVideoLayerEntries(
                for: instruction.timeRange,
                from: videoLayers,
                allocation: allocation
            )
            let layerInstructions = instruction.sourceTrackIDs.compactMap { trackID -> AVMutableVideoCompositionLayerInstruction? in
                guard let track = composition.track(withTrackID: trackID) else { return nil }
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                if let activeLayer = activeClipLayers[trackID] {
                    layerInstruction.setTransform(activeLayer.startState.transform, at: instruction.timeRange.start)
                    if !transformsEqual(activeLayer.startState.transform, activeLayer.endState.transform) {
                        layerInstruction.setTransformRamp(
                            fromStart: activeLayer.startState.transform,
                            toEnd: activeLayer.endState.transform,
                            timeRange: instruction.timeRange
                        )
                    }
                    layerInstruction.setOpacity(activeLayer.startState.opacity, at: instruction.timeRange.start)
                    if !floatsEqual(activeLayer.startState.opacity, activeLayer.endState.opacity) {
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: activeLayer.startState.opacity,
                            toEndOpacity: activeLayer.endState.opacity,
                            timeRange: instruction.timeRange
                        )
                    }
                }
                return layerInstruction
            }
            applyTransitions(to: layerInstructions, timeRange: instruction.timeRange, activeLayers: activeClipLayers)
            mutableInstruction.layerInstructions = layerInstructions
            return mutableInstruction
        }
    }

    private func activeVideoLayerEntries(
        for timeRange: CMTimeRange,
        from videoLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)] {
        var result: [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)] = [:]
        let activeLayers = videoLayers
            .filter { $0.timeRange.start < timeRange.end && $0.timeRange.end > timeRange.start }
            .sorted { lhs, rhs in
                if lhs.layerLevel == rhs.layerLevel {
                    return lhs.timeRange.start < rhs.timeRange.start
                }
                return lhs.layerLevel < rhs.layerLevel
            }

        for layer in activeLayers {
            guard let trackID = allocation[ObjectIdentifier(layer)] else { continue }
            let startState = renderState(for: layer, at: timeRange.start, allocation: allocation)
            let endState = renderState(for: layer, at: timeRange.end, allocation: allocation)
            result[trackID] = (layer, startState, endState)
        }
        return result
    }

    private func applyTransitions(
        to layerInstructions: [AVMutableVideoCompositionLayerInstruction],
        timeRange: CMTimeRange,
        activeLayers: [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)]
    ) {
        for transition in compositionModel.transitions {
            let overlap = CMTimeRangeGetIntersection(timeRange, otherRange: transition.timeRange)
            guard overlap.isValid, !overlap.isEmpty else { continue }
            guard let selectedLayers = layersForTransition(transition, activeLayers: activeLayers) else { continue }

            for layerInstruction in layerInstructions {
                let trackID = layerInstruction.trackID
                if trackID == selectedLayers.sourceTrackID {
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: selectedLayers.source.startState.opacity,
                        toEndOpacity: 0,
                        timeRange: overlap
                    )
                } else if trackID == selectedLayers.destinationTrackID {
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: 0,
                        toEndOpacity: selectedLayers.destination.endState.opacity,
                        timeRange: overlap
                    )
                }
            }
        }
    }

    private func layersForTransition(
        _ transition: Transition,
        activeLayers: [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)]
    ) -> (source: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState), sourceTrackID: CMPersistentTrackID, destination: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState), destinationTrackID: CMPersistentTrackID)? {
        let candidates = activeLayers
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1.layer.layerLevel == rhs.1.layer.layerLevel {
                    return lhs.1.layer.timeRange.start < rhs.1.layer.timeRange.start
                }
                return lhs.1.layer.layerLevel < rhs.1.layer.layerLevel
            }

        guard candidates.count >= 2 else { return nil }

        if let sourceLevel = transition.sourceLayerLevel, let destinationLevel = transition.destinationLayerLevel {
            guard let source = candidates.first(where: { $0.1.layer.layerLevel == sourceLevel }),
                  let destination = candidates.first(where: { $0.1.layer.layerLevel == destinationLevel }) else {
                return nil
            }
            return (source.1, source.0, destination.1, destination.0)
        }

        let source = candidates[0]
        let destination = candidates[1]
        return (source.1, source.0, destination.1, destination.0)
    }

    private func renderState(
        for layer: TimelineLayer,
        at time: CMTime,
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> TimelineLayerRenderState {
        let opacity = KeyframeAnimation.value(for: "opacity", at: time, animations: layer.keyframes) ?? layer.opacity
        let transform = resolvedTransform(for: layer, at: time)
        let kind: TimelineLayerKind
        let trackID: CMPersistentTrackID?
        let image: CGImage?
        let processor: FrameProcessor?
        let effectIntensity: Float?
        if let clipLayer = layer as? ClipLayer {
            kind = .clip
            trackID = allocation[ObjectIdentifier(clipLayer)]
            image = nil
            processor = nil
            effectIntensity = nil
        } else if let imageLayer = layer as? ImageLayer {
            kind = .image
            trackID = nil
            image = imageLayer.image
            processor = nil
            effectIntensity = nil
        } else if layer is TextLayer {
            kind = .text
            trackID = nil
            image = nil
            processor = nil
            effectIntensity = nil
        } else if let effectLayer = layer as? EffectLayer {
            kind = .effect
            trackID = nil
            image = nil
            processor = effectLayer.processor
            effectIntensity = KeyframeAnimation.value(for: "effect.intensity", at: time, animations: effectLayer.keyframes)
                ?? KeyframeAnimation.value(for: "intensity", at: time, animations: effectLayer.keyframes)
                ?? effectLayer.intensity
        } else {
            kind = .effect
            trackID = nil
            image = nil
            processor = nil
            effectIntensity = nil
        }
        return TimelineLayerRenderState(
            kind: kind,
            layerLevel: layer.layerLevel,
            opacity: opacity,
            transform: transform,
            trackID: trackID,
            image: image,
            processor: processor,
            effectIntensity: effectIntensity
        )
    }

    private func resolvedTransform(for layer: TimelineLayer, at time: CMTime) -> CGAffineTransform {
        let baseTransform = layer.transform
        let baseTranslationX = Float(baseTransform.tx)
        let baseTranslationY = Float(baseTransform.ty)
        let baseScaleX = Float(hypot(baseTransform.a, baseTransform.c))
        let baseScaleY = Float(hypot(baseTransform.b, baseTransform.d))
        let baseRotation = Float(atan2(baseTransform.b, baseTransform.a))

        let translationX = KeyframeAnimation.value(for: "translation.x", at: time, animations: layer.keyframes)
            ?? KeyframeAnimation.value(for: "transform.tx", at: time, animations: layer.keyframes)
            ?? baseTranslationX
        let translationY = KeyframeAnimation.value(for: "translation.y", at: time, animations: layer.keyframes)
            ?? KeyframeAnimation.value(for: "transform.ty", at: time, animations: layer.keyframes)
            ?? baseTranslationY
        let scale = KeyframeAnimation.value(for: "scale", at: time, animations: layer.keyframes)
        let scaleX = KeyframeAnimation.value(for: "scale.x", at: time, animations: layer.keyframes)
            ?? scale
            ?? baseScaleX
        let scaleY = KeyframeAnimation.value(for: "scale.y", at: time, animations: layer.keyframes)
            ?? scale
            ?? baseScaleY
        let rotation = KeyframeAnimation.value(for: "rotation", at: time, animations: layer.keyframes)
            ?? baseRotation

        return CGAffineTransform.identity
            .translatedBy(x: CGFloat(translationX), y: CGFloat(translationY))
            .rotated(by: CGFloat(rotation))
            .scaledBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
    }

    private func makeOverlayLayer(
        textLayers: [TextLayer],
        renderSize: CGSize
    ) -> CALayer? {
        guard !textLayers.isEmpty else { return nil }
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        let totalDuration = textLayers.map(\.timeRange.end).max()?.seconds ?? 0
        let overlayDuration = max(totalDuration, compositionModel.frameDuration.seconds)
        for textLayer in textLayers.sorted(by: { $0.layerLevel < $1.layerLevel }) {
            overlayLayer.addSublayer(textLayer.makePresentationLayer(duration: overlayDuration))
        }
        return overlayLayer
    }

    private func uniqueSortedTimes(_ times: [CMTime]) -> [CMTime] {
        let sortedTimes = times.sorted()
        var result: [CMTime] = []
        for time in sortedTimes {
            if let last = result.last, last == time {
                continue
            }
            result.append(time)
        }
        return result
    }

    private func uniqueTrackIDsPreservingOrder(_ trackIDs: [CMPersistentTrackID]) -> [CMPersistentTrackID] {
        var seen: Set<CMPersistentTrackID> = []
        var result: [CMPersistentTrackID] = []
        for trackID in trackIDs where seen.insert(trackID).inserted {
            result.append(trackID)
        }
        return result
    }

    private func floatsEqual(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func transformsEqual(_ lhs: CGAffineTransform, _ rhs: CGAffineTransform, tolerance: CGFloat = 0.0001) -> Bool {
        abs(lhs.a - rhs.a) <= tolerance &&
        abs(lhs.b - rhs.b) <= tolerance &&
        abs(lhs.c - rhs.c) <= tolerance &&
        abs(lhs.d - rhs.d) <= tolerance &&
        abs(lhs.tx - rhs.tx) <= tolerance &&
        abs(lhs.ty - rhs.ty) <= tolerance
    }

    private func ensureTrack(
        in composition: AVMutableComposition,
        mediaType: AVMediaType,
        preferredTrackID: CMPersistentTrackID
    ) -> AVMutableCompositionTrack? {
        if let existing = composition.track(withTrackID: preferredTrackID) {
            return existing
        }
        return composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: preferredTrackID)
    }
}
