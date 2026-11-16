// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
import QuartzCore
@testable import KakaposTimeline

final class TimelineAlgorithmRegressionTests: XCTestCase {
    private func time(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 1_000_000) }
    private func range(_ start: Double, _ duration: Double) -> CMTimeRange { CMTimeRange(start: time(start), duration: time(duration)) }
    private func asset() -> AVAsset {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return AVURLAsset(url: root.appendingPathComponent("KakaposExamples/IMG_3156.MOV"))
    }
    private func clip(_ start: Double = 0, duration: Double = 2, level: Int = 0) -> ClipLayer {
        ClipLayer(asset: asset(), timeRange: range(start, duration), sourceTimeRange: range(0, duration), layerLevel: level)
    }
    private func opacity(_ compiled: CompiledTimelineComposition, at seconds: Double, trackID: CMPersistentTrackID? = nil) throws -> Float {
        let t = time(seconds)
        let instruction = try XCTUnwrap(compiled.videoComposition.instructions.first { CMTimeRangeContainsTime($0.timeRange, time: t) } as? AVVideoCompositionInstruction)
        let layer = try XCTUnwrap(instruction.layerInstructions.first { trackID == nil || $0.trackID == trackID })
        var from: Float = 0; var to: Float = 0; var r = CMTimeRange.invalid
        XCTAssertTrue(layer.getOpacityRamp(for: t, startOpacity: &from, endOpacity: &to, timeRange: &r))
        return r.duration.isNumeric && r.duration > .zero ? from + (to - from) * TimelineCurveSampling.progress(at: t, in: r) : from
    }
    func testInteriorOpacityKeyframeSurvivesCompilation() throws {
        let layer = clip()
        layer.keyframes = [.init(keyPath: "opacity", values: [0, 1, 0], keyTimes: [time(0), time(1), time(2)])]
        let compiled = TimelineComposition(layers: [layer]).compile()
        XCTAssertTrue(compiled.isValid)
        XCTAssertEqual(try opacity(compiled, at: 0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(try opacity(compiled, at: 1), 1, accuracy: 0.001)
        XCTAssertEqual(try opacity(compiled, at: 1.5), 0.5, accuracy: 0.001)
    }
    func testNonlinearOpacityUsesCurveRatherThanEndpointLine() throws {
        let layer = clip()
        layer.keyframes = [.init(keyPath: "opacity", values: [0, 1], keyTimes: [time(0), time(2)], easing: .easeIn)]
        let compiled = TimelineComposition(layers: [layer]).compile()
        for t in [0.25, 0.5, 0.75, 1.25, 1.75] {
            XCTAssertEqual(try opacity(compiled, at: t), Float(pow(t / 2, 2)), accuracy: 0.002)
        }
    }
    func testTransitionKeepsGlobalProgressAcrossUnrelatedCuts() throws {
        let a = clip(duration: 3)
        let b = clip(duration: 3, level: 1)
        let transition = Transition(timeRange: range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)
        let compiled = TimelineComposition(layers: [a, b, EffectLayer(timeRange: range(1, 1), layerLevel: 2)], transitions: [transition]).compile()
        let sourceID = try XCTUnwrap(compiled.renderPlan.assetSegments.first?.compositionTrackID)
        XCTAssertEqual(try opacity(compiled, at: 0.5, trackID: sourceID), 0.75, accuracy: 0.002)
        XCTAssertEqual(try opacity(compiled, at: 1.5, trackID: sourceID), 0.25, accuracy: 0.002)
    }
    func testTransitionEasingIsExecuted() throws {
        let transition = Transition(timeRange: range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1, timingFunction: .easeIn)
        let compiled = TimelineComposition(layers: [clip(), clip(level: 1)], transitions: [transition]).compile()
        let sourceID = try XCTUnwrap(compiled.renderPlan.assetSegments.first?.compositionTrackID)
        XCTAssertEqual(try opacity(compiled, at: 0.5, trackID: sourceID), 0.9375, accuracy: 0.002)
    }
    func testBaseAffineMatricesArePreservedWithoutTransformAnimation() throws {
        for matrix in [CGAffineTransform(scaleX: -1, y: 1), CGAffineTransform.identity.rotated(by: .pi / 4).scaledBy(x: 2, y: 1), CGAffineTransform(a: 1, b: 0.2, c: 0.5, d: 1, tx: 5, ty: 9)] {
            let layer = EffectLayer(timeRange: range(0, 1))
            layer.transform = matrix
            layer.keyframes = [.init(keyPath: "opacity", values: [0, 1], keyTimes: [time(0), time(1)])]
            let states = TimelineComposition(layers: [layer]).compile().renderInstructions.flatMap(\.layerStates)
            XCTAssertTrue(states.allSatisfy { $0.transform == matrix })
        }
    }
    func testRotationSamplingBoundsPixelErrorAtSourceCorners() throws {
        let layer = clip()
        layer.keyframes = [.init(keyPath: "rotation", values: [0, .pi / 2], keyTimes: [time(0), time(2)])]
        let compiled = TimelineComposition(layers: [layer]).compile()
        let size = try XCTUnwrap(layer.asset.tracks(withMediaType: .video).first).naturalSize
        for seconds in [0.1, 0.5, 0.9, 1.3, 1.9] {
            let t = time(seconds)
            let instruction = try XCTUnwrap(compiled.videoComposition.instructions.first { CMTimeRangeContainsTime($0.timeRange, time: t) } as? AVVideoCompositionInstruction)
            let entry = try XCTUnwrap(instruction.layerInstructions.first)
            var from = CGAffineTransform.identity; var to = CGAffineTransform.identity; var r = CMTimeRange.invalid
            XCTAssertTrue(entry.getTransformRamp(for: t, start: &from, end: &to, timeRange: &r))
            let progress = CGFloat(TimelineCurveSampling.progress(at: t, in: r))
            let point = CGPoint(x: size.width, y: size.height)
            let start = point.applying(from)
            let end = point.applying(to)
            let expected = point.applying(CGAffineTransform(rotationAngle: CGFloat(Float.pi / 2) * CGFloat(seconds / 2)))
            XCTAssertEqual(start.x + (end.x - start.x) * progress, expected.x, accuracy: 0.3)
            XCTAssertEqual(start.y + (end.y - start.y) * progress, expected.y, accuracy: 0.3)
        }
    }
    func testTranslationAnimationRetainsMirrorAndShear() throws {
        let layer = EffectLayer(timeRange: range(0, 1))
        layer.transform = CGAffineTransform(a: -1, b: 0.2, c: 0.4, d: 2, tx: 0, ty: 8)
        layer.keyframes = [.init(keyPath: "translation.x", values: [3, 6], keyTimes: [time(0), time(1)])]
        let result = try XCTUnwrap(TimelineComposition(layers: [layer]).compile().renderInstructions.first?.layerStates.first?.transform)
        XCTAssertEqual(result.a, -1); XCTAssertEqual(result.b, 0.2); XCTAssertEqual(result.c, 0.4); XCTAssertEqual(result.d, 2)
        XCTAssertEqual(result.tx, 3); XCTAssertEqual(result.ty, 8)
    }
    func testClippedVolumeRampRetainsOriginalCurveEndpoints() throws {
        let layer = AudioLayer(asset: asset(), timeRange: range(0, 2), sourceTimeRange: range(0, 2), audioRamps: [.init(startVolume: 0, endVolume: 1, timeRange: range(-1, 4))])
        let compiled = TimelineComposition(layers: [layer]).compile()
        let parameters = try XCTUnwrap(compiled.audioMix.inputParameters.first)
        var from: Float = 0; var to: Float = 0; var r = CMTimeRange.invalid
        XCTAssertTrue(parameters.getVolumeRamp(for: time(1), startVolume: &from, endVolume: &to, timeRange: &r))
        XCTAssertEqual(from, 0.25, accuracy: 0.001); XCTAssertEqual(to, 0.75, accuracy: 0.001)
        XCTAssertEqual(r, range(0, 2))
        let descriptor = try XCTUnwrap(compiled.renderPlan.audioMixSegments.first)
        XCTAssertEqual(descriptor.startVolume, 0.25, accuracy: 0.001)
        XCTAssertEqual(descriptor.endVolume, 0.75, accuracy: 0.001)
    }
    func testAudioEasingIsExecuted() throws {
        let layer = AudioLayer(asset: asset(), timeRange: range(0, 2), sourceTimeRange: range(0, 2), audioRamps: [.init(startVolume: 0, endVolume: 1, timeRange: range(0, 2), easing: .easeIn)])
        let parameters = try XCTUnwrap(TimelineComposition(layers: [layer]).compile().audioMix.inputParameters.first)
        var from: Float = 0; var to: Float = 0; var r = CMTimeRange.invalid
        XCTAssertTrue(parameters.getVolumeRamp(for: time(0.5), startVolume: &from, endVolume: &to, timeRange: &r))
        let value = from + (to - from) * TimelineCurveSampling.progress(at: time(0.5), in: r)
        XCTAssertEqual(value, 0.0625, accuracy: 0.002)
    }
    func testTransitionAllowsTrackReuseByLaterClips() throws {
        let transition = Transition(timeRange: range(1, 1), sourceLayerLevel: 0, destinationLayerLevel: 1)
        let compiled = TimelineComposition(layers: [clip(), clip(1, level: 1), clip(3, duration: 1, level: 2)], transitions: [transition]).compile()
        XCTAssertTrue(compiled.isValid)
        let ids = compiled.renderPlan.audioSegments.compactMap(\.compositionTrackID)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 2)
    }
    func testTextOpacityKeyframesReachThePresentationLayer() throws {
        let text = TextLayer(attributedText: NSAttributedString(string: "测试"), frame: CGRect(x: 0, y: 0, width: 100, height: 40), timeRange: range(0, 2))
        text.keyframes = [.init(keyPath: "opacity", values: [0, 1, 0], keyTimes: [time(0), time(1), time(2)])]
        let layer = try XCTUnwrap(TimelineComposition(layers: [text]).compile().overlayLayer?.sublayers?.first)
        let animation = try XCTUnwrap(layer.animation(forKey: "timelineOpacity") as? CAKeyframeAnimation)
        XCTAssertEqual(animation.values as? [Float], [0, 1, 0])
        XCTAssertEqual(animation.keyTimes, [0, 0.5, 1])
    }
    func testTransitionFadeOutDoesNotRestartAfterItsEnd() throws {
        let a = clip(duration: 3)
        let compiled = TimelineComposition(layers: [a, clip(duration: 3, level: 1)], transitions: [Transition(timeRange: range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)]).compile()
        let id = try XCTUnwrap(compiled.renderPlan.assetSegments.first?.compositionTrackID)
        XCTAssertEqual(try opacity(compiled, at: 2.5, trackID: id), 0, accuracy: 0.001)
    }
    func testClipEntranceAndExitTransitionsComposeWithoutOverwritingEachOther() throws {
        let layers = [clip(duration: 4), clip(duration: 4, level: 1), clip(duration: 4, level: 2)]
        let transitions = [Transition(timeRange: range(0, 1), sourceLayerLevel: 0, destinationLayerLevel: 1),
            Transition(timeRange: range(2, 1), sourceLayerLevel: 1, destinationLayerLevel: 2)]
        let compiled = TimelineComposition(layers: layers, transitions: transitions).compile()
        let id = try XCTUnwrap(compiled.renderPlan.assetSegments.first { $0.layerLevel == 1 }?.compositionTrackID)
        XCTAssertEqual(try opacity(compiled, at: 0.5, trackID: id), 0.5, accuracy: 0.002)
        XCTAssertEqual(try opacity(compiled, at: 1.5, trackID: id), 1, accuracy: 0.002)
        XCTAssertEqual(try opacity(compiled, at: 2.5, trackID: id), 0.5, accuracy: 0.002)
    }
    func testTinyKeyframeIntervalReachesItsEndpoint() {
        let curve = KeyframeAnimation(keyPath: "value", values: [0, 1], keyTimes: [time(0), time(0.00001)])
        XCTAssertEqual(curve.value(at: time(0.00001)), 1)
    }
    func testKeyframeLookupUpdatesAfterMutationAndSupportsReverseSeeks() {
        var curve = KeyframeAnimation(keyPath: "value", values: [0, 1, 0], keyTimes: [time(0), time(1), time(2)])
        XCTAssertEqual(curve.value(at: time(1.5)), 0.5)
        XCTAssertEqual(curve.value(at: time(0.5)), 0.5)
        curve.keyTimes = [time(0), time(2), time(4)]
        XCTAssertEqual(curve.value(at: time(1)), 0.5)
    }
    func testUnorderedKeyframesKeepTheFirstMatchingSegment() {
        let curve = KeyframeAnimation(keyPath: "value", values: [0, 2, 1], keyTimes: [time(0), time(2), time(1)])
        XCTAssertEqual(curve.value(at: time(1.5)), 1.5)
        var cursor = 0
        XCTAssertEqual(curve.value(at: time(1.5), cursor: &cursor), 1.5)
    }
    func testKeyframeCursorMatchesPureLookupAcrossForwardAndReverseSeeks() {
        let curve = KeyframeAnimation(keyPath: "value", values: [0, 1, 0], keyTimes: [time(0), time(1), time(2)], easing: .easeIn)
        var index = TimelineKeyframeIndex([curve])
        for t in [0.0, 0.01, 0.02, 0.9, 1, 1.1, 1.9, 0.5, 2, -1, 3] {
            XCTAssertEqual(index.sampledValue(for: "value", at: time(t)), curve.value(at: time(t)))
        }
    }
    func testIntervalIndexMatchesStableHalfOpenScanWithReverseQueries() {
        let layers = (0..<40).map { i in EffectLayer(timeRange: range(Double(i % 10), Double(i % 5 + 1)), layerLevel: i % 3) }
        var index = TimelineIntervalIndex(layers, range: { $0.timeRange }, level: { $0.layerLevel })
        for start in [0.0, 1, 3, 8, 2, 7, 7.5, 1] {
            let r = range(start, 0.5)
            let expected = layers.enumerated().filter { $0.element.timeRange.start < r.end && $0.element.timeRange.end > r.start }.sorted {
                $0.element.layerLevel == $1.element.layerLevel ? $0.offset < $1.offset : $0.element.layerLevel < $1.element.layerLevel
            }.map { ObjectIdentifier($0.element) }
            XCTAssertEqual(index.elements(overlapping: r).map(ObjectIdentifier.init), expected)
        }
    }
}
#endif
