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

    public init(renderSize: CGSize = CGSize(width: 720, height: 1280), frameDuration: CMTime = CMTime(value: 1, timescale: 30), layers: [TimelineLayer] = []) {
        self.renderSize = renderSize
        self.frameDuration = frameDuration
        self.layers = layers
    }

    public func addLayer(_ layer: TimelineLayer) {
        layers.append(layer)
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
        videoComposition.instructions = makeVideoInstructions(from: renderInstructions, composition: composition)
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
            applyAudioRamps(layer.audioRamps, to: parameters)
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
            applyAudioRamps(layer.audioRamps, to: parameters)
            parametersByTrackID[trackID] = parameters
        }

        return parametersByTrackID.keys.sorted().compactMap { parametersByTrackID[$0] }
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
                    sourceTrackIDs: Array(Set(trackIDs)).sorted()
                )
            )
        }

        return instructions
    }

    private func makeVideoInstructions(
        from renderInstructions: [TimelineRenderInstruction],
        composition: AVMutableComposition
    ) -> [AVVideoCompositionInstructionProtocol] {
        renderInstructions.compactMap { instruction in
            let mutableInstruction = AVMutableVideoCompositionInstruction()
            mutableInstruction.timeRange = instruction.timeRange
            let layerInstructions = instruction.sourceTrackIDs.compactMap { trackID -> AVMutableVideoCompositionLayerInstruction? in
                guard let track = composition.track(withTrackID: trackID) else { return nil }
                return AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            }
            mutableInstruction.layerInstructions = layerInstructions
            return mutableInstruction
        }
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
