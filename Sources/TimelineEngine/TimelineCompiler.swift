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
    private struct TransitionBinding {
        let transition: Transition
        let source: ClipLayer
        let destination: ClipLayer
    }
    private var transitionBindings: [TransitionBinding] = []
    private var samplingSizes: [ObjectIdentifier: CGSize] = [:]
    private var keyframeIndexes: [ObjectIdentifier: TimelineKeyframeIndex] = [:]

    init(composition: TimelineComposition) {
        self.compositionModel = TimelineRenderNodeBuilder.build(from: composition)
    }

    func compile() -> CompiledTimelineComposition {
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = compositionModel.renderSize
        videoComposition.frameDuration = compositionModel.frameDuration
        let audioMix = AVMutableAudioMix()
        var diagnostics: [TimelineCompilationDiagnostic] = []

        let flattenedLayers = compositionModel.flattenedLayers()
        let resolvedLayers = resolve(flattenedLayers)
        for layer in flattenedLayers {
            keyframeIndexes[ObjectIdentifier(layer)] = TimelineKeyframeIndex(layer.keyframes)
            guard layer.keyframes.contains(where: { $0.keyPath != "opacity" && $0.keyPath != "intensity" && $0.keyPath != "effect.intensity" }) else { continue }
            let size: CGSize
            if let clip = layer as? ClipLayer { size = clip.asset.tracks(withMediaType: .video).first?.naturalSize ?? compositionModel.renderSize }
            else if let image = layer as? ImageLayer { size = CGSize(width: image.image.width, height: image.image.height) }
            else if let text = layer as? TextLayer { size = text.frame.size }
            else { size = compositionModel.renderSize }
            samplingSizes[ObjectIdentifier(layer)] = size
        }

        let videoAllocation = allocateClipTracks(for: resolvedLayers.videoLayers)
        transitionBindings = compositionModel.transitions.compactMap { transition in
            let candidates = resolvedLayers.videoLayers.filter {
                $0.timeRange.start < transition.timeRange.end && $0.timeRange.end > transition.timeRange.start
            }.sorted { $0.layerLevel == $1.layerLevel ? $0.timeRange.start < $1.timeRange.start : $0.layerLevel < $1.layerLevel }
            guard candidates.count >= 2 else { return nil }
            let source: ClipLayer
            let destination: ClipLayer
            if let sourceLevel = transition.sourceLayerLevel, let destinationLevel = transition.destinationLayerLevel {
                guard let from = candidates.first(where: { $0.layerLevel == sourceLevel }),
                      let to = candidates.first(where: { $0.layerLevel == destinationLevel }) else { return nil }
                source = from
                destination = to
            } else { source = candidates[0]; destination = candidates[1] }
            let overlap = CMTimeRangeGetIntersection(source.timeRange, otherRange: destination.timeRange)
            guard source !== destination, CMTimeRangeGetIntersection(overlap, otherRange: transition.timeRange).duration > .zero else { return nil }
            return TransitionBinding(transition: transition, source: source, destination: destination)
        }
        let audioAllocation = allocateAudioTracks(
            clipLayers: resolvedLayers.videoLayers,
            audioLayers: resolvedLayers.audioLayers
        )

        insertVideoLayers(
            resolvedLayers.videoLayers,
            allocation: videoAllocation,
            into: composition,
            diagnostics: &diagnostics
        )
        let audioParameters = insertAudioLayers(
            clipLayers: resolvedLayers.videoLayers,
            audioLayers: resolvedLayers.audioLayers,
            allocation: audioAllocation,
            into: composition,
            diagnostics: &diagnostics
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
            overlayLayer: overlayLayer,
            diagnostics: diagnostics
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
        guard let earliest = trackEndTimes.min(by: {
            $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
        }), earliest.value <= start else { return nil }
        return earliest.key
    }

    private func insertVideoLayers(
        _ layers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        into composition: AVMutableComposition,
        diagnostics: inout [TimelineCompilationDiagnostic]
    ) {
        for layer in layers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .video).first else {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.video.rawValue,
                    description: "source video track is missing"
                ))
                continue
            }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            if let description = invalidSourceRangeDescription(sourceRange, for: sourceTrack) {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.video.rawValue,
                    description: description
                ))
                continue
            }
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .video,
                    preferredTrackID: trackID
                  ) else {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.video.rawValue,
                    description: "composition video track could not be allocated"
                ))
                continue
            }

            do {
                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
                compositionTrack.preferredTransform = sourceTrack.preferredTransform
            } catch {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.video.rawValue,
                    description: error.localizedDescription
                ))
            }
        }
    }

    private func insertAudioLayers(
        clipLayers: [ClipLayer],
        audioLayers: [AudioLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        into composition: AVMutableComposition,
        diagnostics: inout [TimelineCompilationDiagnostic]
    ) -> [AVMutableAudioMixInputParameters] {
        var parametersByTrackID: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        for layer in clipLayers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .audio).first else { continue }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            if let description = invalidSourceRangeDescription(sourceRange, for: sourceTrack) {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: description
                ))
                continue
            }
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .audio,
                    preferredTrackID: trackID
                  ) else {
                continue
            }

            do {
                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
            } catch {
                diagnostics.append(.init(
                    layerKind: .clip,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: error.localizedDescription
                ))
                continue
            }
            let parameters = parametersByTrackID[trackID] ?? AVMutableAudioMixInputParameters(track: compositionTrack)
            applyClipAudioMix(layer, to: parameters)
            parametersByTrackID[trackID] = parameters
        }

        for layer in audioLayers {
            guard let sourceTrack = layer.asset.tracks(withMediaType: .audio).first else {
                diagnostics.append(.init(
                    layerKind: .audio,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: "source audio track is missing"
                ))
                continue
            }
            let sourceRange = layer.sourceTimeRange ?? sourceTrack.timeRange
            if let description = invalidSourceRangeDescription(sourceRange, for: sourceTrack) {
                diagnostics.append(.init(
                    layerKind: .audio,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: description
                ))
                continue
            }
            guard let trackID = allocation[ObjectIdentifier(layer)],
                  let compositionTrack = ensureTrack(
                    in: composition,
                    mediaType: .audio,
                    preferredTrackID: trackID
                  ) else {
                diagnostics.append(.init(
                    layerKind: .audio,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: "composition audio track could not be allocated"
                ))
                continue
            }

            do {
                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: layer.timeRange.start)
            } catch {
                diagnostics.append(.init(
                    layerKind: .audio,
                    layerLevel: layer.layerLevel,
                    mediaType: AVMediaType.audio.rawValue,
                    description: error.localizedDescription
                ))
                continue
            }
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

    private func invalidSourceRangeDescription(_ range: CMTimeRange, for track: AVAssetTrack) -> String? {
        guard range.isValid, range.isEmpty == false, range.duration > .zero else {
            return "source time range is invalid or empty"
        }
        let availableRange = track.timeRange
        guard availableRange.isValid,
              range.start >= availableRange.start,
              range.end <= availableRange.end else {
            return "source time range is outside the available track range"
        }
        return nil
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
            applyVolumeCurve(in: clippedRange, to: parameters) { time in
                let progress = TimelineCurveSampling.progress(at: time, in: ramp.timeRange)
                let fraction = ramp.timingFunction.value(at: progress)
                return (ramp.startVolume + fraction * (ramp.endVolume - ramp.startVolume)) * baseVolume
            }
        }
    }

    private func applyVolumeCurve(
        in range: CMTimeRange,
        to parameters: AVMutableAudioMixInputParameters,
        value: (CMTime) -> Float
    ) {
        let times = TimelineCurveSampling.times(in: range, minimumStep: CMTime(value: 1, timescale: 48_000)) {
            [Double(value($0))]
        }
        for (start, end) in zip(times, times.dropFirst()) {
            parameters.setVolumeRamp(fromStartVolume: value(start), toEndVolume: value(end),
                timeRange: CMTimeRange(start: start, end: end))
        }
    }

    private func applyTransitionAudioMix(
        clipLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID],
        parametersByTrackID: inout [CMPersistentTrackID: AVMutableAudioMixInputParameters]
    ) {
        for transition in compositionModel.transitions where transition.kind == .crossDissolve && transition.audioBehavior == .crossfade {
            let candidates = clipLayers.filter {
                $0.timeRange.start < transition.timeRange.end && $0.timeRange.end > transition.timeRange.start
            }
            let times = uniqueSortedTimes([transition.timeRange.start, transition.timeRange.end] + candidates.flatMap {
                [max($0.timeRange.start, transition.timeRange.start), min($0.timeRange.end, transition.timeRange.end)]
            })
            var index = TimelineIntervalIndex(candidates, range: { $0.timeRange }, level: { $0.layerLevel })
            for (start, end) in zip(times, times.dropFirst()) where end > start {
                let range = CMTimeRange(start: start, end: end)
                let active = activeVideoLayerEntries(for: range, from: index.elements(overlapping: range), allocation: allocation)
                guard let selected = layersForTransition(transition, activeLayers: active) else { continue }
                for (trackID, volume, fadesIn) in [
                    (selected.sourceTrackID, selected.source.layer.volume, false),
                    (selected.destinationTrackID, selected.destination.layer.volume, true)
                ] {
                    guard let parameters = parametersByTrackID[trackID] else { continue }
                    applyVolumeCurve(in: range, to: parameters) { time in
                        let progress = transition.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: transition.timeRange))
                        return volume * (fadesIn ? progress : 1 - progress)
                    }
                }
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
        // 先收集原始边界，保留等值 CMTime 首次出现的时间刻度。
        var times = activeLayers.flatMap { [$0.timeRange.start, $0.timeRange.end] }
        times += activeLayers.flatMap { layer in
            layer.keyframes.flatMap(\.keyTimes).filter {
                $0.isNumeric && $0 > layer.timeRange.start && $0 < layer.timeRange.end
            }
        }
        let cutPoints = uniqueSortedTimes(times)
        var index = TimelineIntervalIndex(activeLayers, range: { $0.timeRange }, level: { $0.layerLevel })
        var instructions: [TimelineRenderInstruction] = []
        for (start, end) in zip(cutPoints, cutPoints.dropFirst()) {
            let timeRange = CMTimeRange(start: start, end: end)
            let intervalLayers = index.elements(overlapping: timeRange)
            guard !intervalLayers.isEmpty else { continue }
            let trackIDs = intervalLayers.compactMap { allocation[ObjectIdentifier($0)] }
            instructions.append(TimelineRenderInstruction(
                timeRange: timeRange,
                layerLevels: intervalLayers.map(\.layerLevel),
                sourceTrackIDs: uniqueTrackIDsPreservingOrder(trackIDs),
                layerStates: intervalLayers.map { renderState(for: $0, at: start, allocation: allocation) },
                processors: intervalLayers.compactMap { ($0 as? EffectLayer)?.processor }
            ))
        }
        return instructions
    }

    private func visualSampleTimes(
        in range: CMTimeRange,
        layers: [TimelineLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [CMTime] {
        let bindings = transitionBindings.filter { binding in
            layers.contains { $0 === binding.source || $0 === binding.destination }
        }
        guard layers.contains(where: { !$0.keyframes.isEmpty }) || !bindings.isEmpty else { return [range.start, range.end] }
        let boundaries = uniqueSortedTimes([range.start, range.end] + bindings.flatMap {
            [$0.transition.timeRange.start, $0.transition.timeRange.end].filter { $0 > range.start && $0 < range.end }
        } + layers.flatMap { $0.keyframes.flatMap(\.keyTimes).filter { $0.isNumeric && $0 > range.start && $0 < range.end } })
        var samples: [CMTime] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let times = TimelineCurveSampling.times(in: CMTimeRange(start: start, end: end),
                minimumStep: CMTimeMultiplyByFloat64(compositionModel.frameDuration, multiplier: 0.125)) { time in
                layers.flatMap { layer -> [Double] in
                    let state = renderState(for: layer, at: time, allocation: allocation)
                    let m = state.transform
                    let size = samplingSizes[ObjectIdentifier(layer)] ?? compositionModel.renderSize
                    let w = Double(size.width)
                    let h = Double(size.height)
                    // 以源图四角的输出像素误差采样，避免大图放大矩阵系数误差。
                    let x = Double(m.tx)
                    let y = Double(m.ty)
                    let ax = Double(m.a) * w
                    let ay = Double(m.b) * w
                    let bx = Double(m.c) * h
                    let by = Double(m.d) * h
                    return [Double(effectiveOpacity(for: layer, at: time)), x / 250, y / 250,
                        (ax + x) / 250, (ay + y) / 250, (bx + x) / 250, (by + y) / 250,
                        (ax + bx + x) / 250, (ay + by + y) / 250, Double(state.effectIntensity ?? 0)]
                }
            }
            samples += samples.isEmpty ? times : Array(times.dropFirst())
        }
        return samples
    }

    private func makeVideoInstructions(
        from renderInstructions: [TimelineRenderInstruction],
        composition: AVMutableComposition,
        videoLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [AVVideoCompositionInstructionProtocol] {
        var index = TimelineIntervalIndex(videoLayers, range: { $0.timeRange }, level: { $0.layerLevel })
        var result: [AVVideoCompositionInstructionProtocol] = []
        for instruction in renderInstructions {
            let layers = index.elements(overlapping: instruction.timeRange)
            let times = visualSampleTimes(in: instruction.timeRange, layers: layers, allocation: allocation)
            for (start, end) in zip(times, times.dropFirst()) {
                let range = CMTimeRange(start: start, end: end)
                let active = activeVideoLayerEntries(for: range, from: layers, allocation: allocation)
                let output = AVMutableVideoCompositionInstruction()
                output.timeRange = range
                let layerInstructions = instruction.sourceTrackIDs.compactMap { trackID -> AVMutableVideoCompositionLayerInstruction? in
                    guard let track = composition.track(withTrackID: trackID), let layer = active[trackID] else { return nil }
                    let entry = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                    entry.setTransform(layer.startState.transform, at: start)
                    if !transformsEqual(layer.startState.transform, layer.endState.transform) {
                        entry.setTransformRamp(fromStart: layer.startState.transform, toEnd: layer.endState.transform, timeRange: range)
                    }
                    entry.setOpacity(layer.startState.opacity, at: start)
                    if !floatsEqual(layer.startState.opacity, layer.endState.opacity) {
                        entry.setOpacityRamp(fromStartOpacity: layer.startState.opacity, toEndOpacity: layer.endState.opacity, timeRange: range)
                    }
                    return entry
                }
                applyTransitions(to: layerInstructions, timeRange: range, activeLayers: active)
                output.layerInstructions = layerInstructions
                result.append(output)
            }
        }
        return result
    }

    private func activeVideoLayerEntries(
        for timeRange: CMTimeRange,
        from orderedVideoLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)] {
        var result: [CMPersistentTrackID: (layer: ClipLayer, startState: TimelineLayerRenderState, endState: TimelineLayerRenderState)] = [:]
        for layer in orderedVideoLayers {
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
        for instruction in layerInstructions {
            guard let layer = activeLayers[instruction.trackID]?.layer,
                  transitionBindings.contains(where: { $0.source === layer || $0.destination === layer }) else { continue }
            instruction.setOpacityRamp(fromStartOpacity: effectiveOpacity(for: layer, at: timeRange.start),
                toEndOpacity: effectiveOpacity(for: layer, at: timeRange.end), timeRange: timeRange)
        }
    }

    private func effectiveOpacity(for layer: TimelineLayer, at time: CMTime) -> Float {
        let base = opacity(for: layer, at: time)
        var result = base
        for binding in transitionBindings {
            if binding.source === layer { result *= 1 - transitionProgress(binding.transition, at: time) }
            if binding.destination === layer { result *= transitionProgress(binding.transition, at: time) }
        }
        return result
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
        let opacity = opacity(for: layer, at: time)
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
            effectIntensity = keyframeValue("effect.intensity", for: effectLayer, at: time)
                ?? keyframeValue("intensity", for: effectLayer, at: time)
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

    private func keyframeValue(_ keyPath: String, for layer: TimelineLayer, at time: CMTime) -> Float? {
        keyframeIndexes[ObjectIdentifier(layer)]?.value(for: keyPath, at: time)
    }

    private func opacity(for layer: TimelineLayer, at time: CMTime) -> Float {
        keyframeValue("opacity", for: layer, at: time) ?? layer.opacity
    }

    private func transitionProgress(_ transition: Transition, at time: CMTime) -> Float {
        transition.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: transition.timeRange))
    }

    private func resolvedTransform(for layer: TimelineLayer, at time: CMTime) -> CGAffineTransform {
        let base = layer.transform
        func value(_ key: String) -> CGFloat? { keyframeValue(key, for: layer, at: time).map(CGFloat.init) }
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
            let layer = textLayer.makePresentationLayer(duration: overlayDuration)
            if textLayer.timeRange.duration.isNumeric, textLayer.timeRange.duration > .zero, !textLayer.keyframes.isEmpty {
                let times = visualSampleTimes(in: textLayer.timeRange, layers: [textLayer], allocation: [:])
                let keys = times.map { NSNumber(value: TimelineCurveSampling.progress(at: $0, in: textLayer.timeRange)) }
                if textLayer.keyframes.contains(where: { $0.keyPath == "opacity" }) {
                    layer.removeAnimation(forKey: "timelineVisibility")
                    layer.opacity = 0
                    let animation = CAKeyframeAnimation(keyPath: "opacity")
                    animation.values = times.map { opacity(for: textLayer, at: $0) }
                    animation.keyTimes = keys
                    animation.duration = textLayer.timeRange.duration.seconds
                    animation.beginTime = AVCoreAnimationBeginTimeAtZero + textLayer.timeRange.start.seconds
                    animation.isRemovedOnCompletion = false
                    layer.add(animation, forKey: "timelineOpacity")
                }
                let animation = CAKeyframeAnimation(keyPath: "transform")
                animation.values = times.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform(resolvedTransform(for: textLayer, at: $0))) }
                animation.keyTimes = keys
                animation.duration = textLayer.timeRange.duration.seconds
                animation.beginTime = AVCoreAnimationBeginTimeAtZero + textLayer.timeRange.start.seconds
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: "timelineTransform")
            }
            overlayLayer.addSublayer(layer)
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

    private func transformsEqual(_ lhs: CGAffineTransform, _ rhs: CGAffineTransform, tolerance: CGFloat = 0) -> Bool {
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
