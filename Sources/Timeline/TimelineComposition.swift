//
//  TimelineComposition.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics

public struct TimelineRenderInstruction {
    public let timeRange: CMTimeRange
    public let layerLevels: [Int]
    public let sourceTrackIDs: [CMPersistentTrackID]
}

public struct ResolvedTimelineLayers {
    public let videoLayers: [ClipLayer]
    public let imageLayers: [ImageLayer]
    public let audioLayers: [AudioLayer]
    public let effectLayers: [EffectLayer]
}

public struct CompiledTimelineComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let renderInstructions: [TimelineRenderInstruction]
    public let resolvedLayers: ResolvedTimelineLayers
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
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        let audioMix = AVMutableAudioMix()

        let flattenedLayers = flattenLayers(layers)
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

        return CompiledTimelineComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            renderInstructions: renderInstructions,
            resolvedLayers: resolvedLayers
        )
    }

    private func flattenLayers(_ input: [TimelineLayer]) -> [TimelineLayer] {
        input.flatMap { layer -> [TimelineLayer] in
            if let group = layer as? GroupLayer {
                return flattenLayers(group.layers.map { $0.applyingOffset(group.timeRange.start, inheritedLevel: group.layerLevel) })
            }
            return [layer]
        }
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

    private func applyAudioRamps(_ ramps: [AudioVolumeRamp], to parameters: AVMutableAudioMixInputParameters) {
        for ramp in ramps {
            parameters.setVolumeRamp(
                fromStartVolume: ramp.startVolume,
                toEndVolume: ramp.endVolume,
                timeRange: ramp.timeRange
            )
        }
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
        guard !transitions.isEmpty else { return }
        let layerByTrackID = Dictionary(
            uniqueKeysWithValues: clipLayers.compactMap { layer -> (CMPersistentTrackID, ClipLayer)? in
                guard let trackID = allocation[ObjectIdentifier(layer)] else { return nil }
                return (trackID, layer)
            }
        )

        for transition in transitions where transition.kind == .crossDissolve {
            guard let selectedLayers = layersForTransition(transition, activeLayers: layerByTrackID) else { continue }
            let overlap = CMTimeRangeGetIntersection(transition.timeRange, otherRange: selectedLayers.source.timeRange)
            let transitionRange = CMTimeRangeGetIntersection(overlap, otherRange: selectedLayers.destination.timeRange)
            guard transitionRange.isValid, !transitionRange.isEmpty else { continue }

            if let sourceParameters = parametersByTrackID[selectedLayers.sourceTrackID] {
                sourceParameters.setVolumeRamp(
                    fromStartVolume: selectedLayers.source.volume,
                    toEndVolume: 0,
                    timeRange: transitionRange
                )
            }

            if let destinationParameters = parametersByTrackID[selectedLayers.destinationTrackID] {
                destinationParameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: selectedLayers.destination.volume,
                    timeRange: transitionRange
                )
            }
        }
    }

    private func buildRenderInstructions(
        videoLayers: [ClipLayer],
        imageLayers: [ImageLayer],
        effectLayers: [EffectLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [TimelineRenderInstruction] {
        let visualLayers = (videoLayers as [TimelineLayer]) + imageLayers + effectLayers
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
                    sourceTrackIDs: uniqueTrackIDsPreservingOrder(trackIDs)
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
            let activeClipLayers = activeVideoLayers(
                for: instruction.timeRange,
                from: videoLayers,
                allocation: allocation
            )
            let layerInstructions = instruction.sourceTrackIDs.compactMap { trackID -> AVMutableVideoCompositionLayerInstruction? in
                guard let track = composition.track(withTrackID: trackID) else { return nil }
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                if let activeLayer = activeClipLayers[trackID] {
                    layerInstruction.setTransform(activeLayer.transform, at: instruction.timeRange.start)
                    layerInstruction.setOpacity(activeLayer.opacity, at: instruction.timeRange.start)
                }
                return layerInstruction
            }
            applyTransitions(to: layerInstructions, timeRange: instruction.timeRange, activeLayers: activeClipLayers)
            mutableInstruction.layerInstructions = layerInstructions
            return mutableInstruction
        }
    }

    private func activeVideoLayers(
        for timeRange: CMTimeRange,
        from videoLayers: [ClipLayer],
        allocation: [ObjectIdentifier: CMPersistentTrackID]
    ) -> [CMPersistentTrackID: ClipLayer] {
        var result: [CMPersistentTrackID: ClipLayer] = [:]
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
            result[trackID] = layer
        }
        return result
    }

    private func applyTransitions(
        to layerInstructions: [AVMutableVideoCompositionLayerInstruction],
        timeRange: CMTimeRange,
        activeLayers: [CMPersistentTrackID: ClipLayer]
    ) {
        for transition in transitions {
            let overlap = CMTimeRangeGetIntersection(timeRange, otherRange: transition.timeRange)
            guard overlap.isValid, !overlap.isEmpty else { continue }
            guard let selectedLayers = layersForTransition(transition, activeLayers: activeLayers) else { continue }

            for layerInstruction in layerInstructions {
                let trackID = layerInstruction.trackID
                if trackID == selectedLayers.sourceTrackID {
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: selectedLayers.source.opacity,
                        toEndOpacity: 0,
                        timeRange: overlap
                    )
                } else if trackID == selectedLayers.destinationTrackID {
                    layerInstruction.setOpacityRamp(
                        fromStartOpacity: 0,
                        toEndOpacity: selectedLayers.destination.opacity,
                        timeRange: overlap
                    )
                }
            }
        }
    }

    private func layersForTransition(
        _ transition: Transition,
        activeLayers: [CMPersistentTrackID: ClipLayer]
    ) -> (source: ClipLayer, sourceTrackID: CMPersistentTrackID, destination: ClipLayer, destinationTrackID: CMPersistentTrackID)? {
        let candidates = activeLayers
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1.layerLevel == rhs.1.layerLevel {
                    return lhs.1.timeRange.start < rhs.1.timeRange.start
                }
                return lhs.1.layerLevel < rhs.1.layerLevel
            }

        guard candidates.count >= 2 else { return nil }

        if let sourceLevel = transition.sourceLayerLevel, let destinationLevel = transition.destinationLayerLevel {
            guard let source = candidates.first(where: { $0.1.layerLevel == sourceLevel }),
                  let destination = candidates.first(where: { $0.1.layerLevel == destinationLevel }) else {
                return nil
            }
            return (source.1, source.0, destination.1, destination.0)
        }

        let source = candidates[0]
        let destination = candidates[1]
        return (source.1, source.0, destination.1, destination.0)
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
