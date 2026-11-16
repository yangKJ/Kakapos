// 作者：Condy
import Foundation
import AVFoundation

struct TimelineTransitionBinding {
    let index: Int
    let transition: Transition
    let timeRange: CMTimeRange
    let source: ClipLayer
    let destination: ClipLayer
}

struct TimelineTransitionEnvelope {
    let index: Int
    let transition: Transition
    let spans: [(range: CMTimeRange, fadesIn: Bool)]

    func fadesIn(at time: CMTime) -> Bool {
        var low = 0
        var high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if spans[middle].range.start <= time { low = middle + 1 } else { high = middle }
        }
        return spans[max(0, low - 1)].fadesIn
    }
    func value(at time: CMTime) -> Float {
        let progress = transition.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: transition.timeRange))
        return fadesIn(at: time) ? progress : 1 - progress
    }
}

struct TimelineTransitionPlan {
    let bindings: [TimelineTransitionBinding]
    let envelopes: [ObjectIdentifier: [TimelineTransitionEnvelope]]
    nonisolated(unsafe) static let empty = TimelineTransitionPlan(layers: [], transitions: [])

    init(layers: [ClipLayer], transitions: [Transition]) {
        var bindings: [TimelineTransitionBinding] = []
        for (index, transition) in transitions.enumerated() {
            let candidates = layers.filter { $0.timeRange.start < transition.timeRange.end && $0.timeRange.end > transition.timeRange.start }
            let points = Self.times([transition.timeRange.start, transition.timeRange.end] + candidates.flatMap {
                [max($0.timeRange.start, transition.timeRange.start), min($0.timeRange.end, transition.timeRange.end)]
            })
            var active = TimelineIntervalIndex(candidates, range: { $0.timeRange }, level: { $0.layerLevel })
            for (start, end) in zip(points, points.dropFirst()) where end > start {
                let range = CMTimeRange(start: start, end: end)
                let entries = active.elements(overlapping: range)
                guard entries.count >= 2 else { continue }
                let source: ClipLayer
                let destination: ClipLayer
                if let sourceLevel = transition.sourceLayerLevel, let destinationLevel = transition.destinationLayerLevel {
                    guard let from = entries.first(where: { $0.layerLevel == sourceLevel }),
                          let to = entries.first(where: { $0.layerLevel == destinationLevel }) else { continue }
                    source = from; destination = to
                } else { source = entries[0]; destination = entries[1] }
                guard source !== destination else { continue }
                if let last = bindings.last, last.index == index, last.source === source, last.destination === destination,
                   last.timeRange.end == start {
                    bindings[bindings.count - 1] = TimelineTransitionBinding(index: index, transition: transition,
                        timeRange: CMTimeRange(start: last.timeRange.start, end: end), source: source, destination: destination)
                } else {
                    bindings.append(TimelineTransitionBinding(index: index, transition: transition, timeRange: range, source: source, destination: destination))
                }
            }
        }
        self.bindings = bindings
        var grouped: [ObjectIdentifier: [Int: [(CMTimeRange, Bool)]]] = [:]
        for binding in bindings {
            grouped[ObjectIdentifier(binding.source), default: [:]][binding.index, default: []].append((binding.timeRange, false))
            grouped[ObjectIdentifier(binding.destination), default: [:]][binding.index, default: []].append((binding.timeRange, true))
        }
        self.envelopes = grouped.mapValues { byTransition in
            byTransition.keys.sorted().map { index in
                var spans: [(range: CMTimeRange, fadesIn: Bool)] = []
                for value in byTransition[index]! {
                    if let last = spans.last, last.fadesIn == value.1, last.range.end == value.0.start {
                        spans[spans.count - 1] = (CMTimeRange(start: last.range.start, end: value.0.end), value.1)
                    } else { spans.append((value.0, value.1)) }
                }
                return TimelineTransitionEnvelope(index: index, transition: transitions[index], spans: spans)
            }
        }
    }

    func factor(for layer: TimelineLayer, at time: CMTime, audio: Bool = false) -> Float {
        (envelopes[ObjectIdentifier(layer)] ?? []).reduce(1) { value, envelope in
            audio && envelope.transition.audioBehavior != .crossfade ? value : value * envelope.value(at: time)
        }
    }

    static func times(_ input: [CMTime]) -> [CMTime] {
        var result: [CMTime] = []
        for time in input.sorted() where result.last != time { result.append(time) }
        return result
    }
}

struct TimelineAudioEnvelope {
    let timeRange: CMTimeRange
    let volume: Float
    let ramps: [AudioVolumeRamp]
    let transitions: [TimelineTransitionEnvelope]

    func segments(trackID: CMPersistentTrackID?, level: Int) -> [TimelineAudioMixSegment] {
        let enabled = transitions.filter { $0.transition.audioBehavior == .crossfade }
        let boundaries = TimelineTransitionPlan.times([timeRange.start, timeRange.end] + ramps.flatMap { [$0.timeRange.start, $0.timeRange.end] }
            + enabled.flatMap { [$0.transition.timeRange.start, $0.transition.timeRange.end] + $0.spans.flatMap { [$0.range.start, $0.range.end] } })
            .filter { $0 >= timeRange.start && $0 <= timeRange.end }
        let orderedRamps = ramps.enumerated().sorted {
            $0.element.timeRange.start == $1.element.timeRange.start ? $0.offset < $1.offset : $0.element.timeRange.start < $1.element.timeRange.start
        }.map(\.element)
        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            guard end > start else { return nil }
            let range = CMTimeRange(start: start, end: end)
            let middle = start + CMTimeMultiplyByFloat64(end - start, multiplier: 0.5)
            var low = 0
            var high = orderedRamps.count
            while low < high {
                let middleIndex = (low + high) / 2
                if orderedRamps[middleIndex].timeRange.start <= middle { low = middleIndex + 1 } else { high = middleIndex }
            }
            let ramp = low > 0 ? orderedRamps[low - 1] : nil
            let relevant = enabled.filter { $0.transition.timeRange.start < end && $0.transition.timeRange.end > start }
            let kind: TimelineAudioMixSegment.Kind = relevant.last.map { $0.fadesIn(at: middle) ? .transitionFadeIn : .transitionFadeOut } ?? .layerRamp
            let evaluate: (CMTime) -> Float = { time in
                let base: Float
                if let ramp {
                    let p = ramp.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: ramp.timeRange))
                    base = self.volume * (ramp.startVolume + (ramp.endVolume - ramp.startVolume) * p)
                } else { base = self.volume }
                return enabled.reduce(base) { $0 * $1.value(at: time) }
            }
            var segment = TimelineAudioMixSegment(kind: kind, compositionTrackID: trackID, timeRange: range,
                layerLevel: level, startVolume: evaluate(start), endVolume: evaluate(end),
                timingFunction: relevant.count == 1 && ramp == nil ? relevant[0].transition.timingFunction : (enabled.isEmpty ? ramp?.timingFunction ?? .linear : .linear))
            segment.evaluator = evaluate
            segment.isControlSegment = !relevant.isEmpty || ramps.contains { $0.timeRange.start < end && $0.timeRange.end > start }
            return segment
        }
    }
}
