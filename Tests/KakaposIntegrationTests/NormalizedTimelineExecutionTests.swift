// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
@testable import KakaposMediaCore
@testable import KakaposVideo
@testable import KakaposTimeline

final class NormalizedTimelineExecutionTests: XCTestCase {
    private func clip(_ start: Double, _ duration: Double, _ level: Int) -> ClipLayer {
        ClipLayer(asset: Round2Fixtures.asset(), timeRange: Round2Fixtures.range(start, duration),
            sourceTimeRange: Round2Fixtures.range(0, duration), layerLevel: level)
    }
    private func opacity(_ compiled: CompiledTimelineComposition, level: Int, at time: Double) throws -> Float {
        let t = Round2Fixtures.time(time)
        let segment = try XCTUnwrap(compiled.renderPlan.assetSegments.first { $0.layerLevel == level && CMTimeRangeContainsTime($0.destinationTimeRange, time: t) })
        let instruction = try XCTUnwrap(compiled.videoComposition.instructions.first { CMTimeRangeContainsTime($0.timeRange, time: t) } as? AVVideoCompositionInstruction)
        let entry = try XCTUnwrap(instruction.layerInstructions.first { $0.trackID == segment.compositionTrackID })
        var from: Float = 0; var to: Float = 0; var range = CMTimeRange.invalid
        XCTAssertTrue(entry.getOpacityRamp(for: t, startOpacity: &from, endOpacity: &to, timeRange: &range))
        return range.duration.isNumeric ? from + (to - from) * TimelineCurveSampling.progress(at: t, in: range) : from
    }
    private func gain(_ compiled: CompiledTimelineComposition, level: Int, at time: Double) throws -> Float {
        let t = Round2Fixtures.time(time)
        let segment = try XCTUnwrap(compiled.renderPlan.audioSegments.first { $0.layerLevel == level && CMTimeRangeContainsTime($0.destinationTimeRange, time: t) })
        let entry = try XCTUnwrap(compiled.audioMix.inputParameters.first { $0.trackID == segment.compositionTrackID })
        var from: Float = 0; var to: Float = 0; var range = CMTimeRange.invalid
        XCTAssertTrue(entry.getVolumeRamp(for: t, startVolume: &from, endVolume: &to, timeRange: &range))
        return range.duration.isNumeric ? from + (to - from) * TimelineCurveSampling.progress(at: t, in: range) : from
    }
    func testExplicitDurationMismatchIsDiagnosedBeforeExport() {
        let a = clip(0, 1, 0); a.sourceTimeRange = Round2Fixtures.range(0, 2)
        let b = clip(1, 1, 0); b.sourceTimeRange = Round2Fixtures.range(0, 2)
        let result = TimelineComposition(layers: [a, b]).compile()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains { $0.description.contains("durations differ") })
        XCTAssertEqual(result.composition.duration, .zero)
    }
    func testImplicitSourceRangesCropToDestinationWithoutShiftingLaterClips() {
        let a = ClipLayer(asset: Round2Fixtures.asset(), timeRange: Round2Fixtures.range(0, 1))
        let b = ClipLayer(asset: Round2Fixtures.asset(), timeRange: Round2Fixtures.range(1, 1))
        let result = TimelineComposition(layers: [a, b]).compile()
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.composition.duration.seconds, 2, accuracy: 0.001)
        XCTAssertTrue(result.renderPlan.assetSegments.allSatisfy { $0.source.sourceTimeRange?.duration.seconds == 1 })
    }
    func testGroupLocalClockAndParentChildStateCompose() throws {
        let child = EffectLayer(timeRange: Round2Fixtures.range(0, 2))
        child.transform = CGAffineTransform(scaleX: 2, y: 1)
        child.keyframes = [.init(keyPath: "translation.x", values: [0, 5, 10], keyTimes: [Round2Fixtures.time(0), Round2Fixtures.time(1), Round2Fixtures.time(2)]),
            .init(keyPath: "opacity", values: [0.2, 0.5, 0.8], keyTimes: [Round2Fixtures.time(0), Round2Fixtures.time(1), Round2Fixtures.time(2)])]
        let parent = GroupLayer(timeRange: Round2Fixtures.range(10, 2), layers: [child])
        parent.transform = CGAffineTransform(translationX: 100, y: 0); parent.opacity = 0.5
        let compiled = TimelineComposition(layers: [parent]).compile()
        let first = try XCTUnwrap(compiled.renderInstructions.first?.layerStates.first)
        XCTAssertEqual(first.opacity, 0.1, accuracy: 0.0001)
        XCTAssertEqual(first.transform.tx, 100, accuracy: 0.001)
        let middle = try XCTUnwrap(compiled.renderInstructions.first { $0.timeRange.start == Round2Fixtures.time(11) }?.layerStates.first)
        XCTAssertEqual(middle.opacity, 0.25, accuracy: 0.0001)
        XCTAssertEqual(middle.transform.tx, 105, accuracy: 0.001)
        XCTAssertEqual(CGPoint(x: 1, y: 0).applying(middle.transform).x, 107, accuracy: 0.001)
    }
    func testNormalizedLeafCanBeMovedAndCompiledAgainWithoutLosingItsParent() throws {
        let child = EffectLayer(timeRange: Round2Fixtures.range(0, 2))
        child.keyframes = [.init(keyPath: "translation.x", values: [0, 10], keyTimes: [.zero, Round2Fixtures.time(2)])]
        let group = GroupLayer(timeRange: Round2Fixtures.range(0, 2), layers: [child])
        group.transform = CGAffineTransform(translationX: 100, y: 0)
        let first = TimelineComposition(layers: [group]).compile()
        let leaf = try XCTUnwrap(first.resolvedLayers.effectLayers.first)
        let second = TimelineComposition(layers: [leaf.applyingOffset(Round2Fixtures.time(5))]).compile()
        XCTAssertEqual(second.renderInstructions.first?.timeRange.start, Round2Fixtures.time(5))
        XCTAssertEqual(second.renderInstructions.first?.layerStates.first?.transform.tx, 100)
    }
    func testMovingGroupDoesNotApplyItsOffsetTwice() throws {
        let child = EffectLayer(timeRange: Round2Fixtures.range(0, 2))
        child.keyframes = [.init(keyPath: "opacity", values: [0, 1], keyTimes: [.zero, Round2Fixtures.time(2)])]
        let group = GroupLayer(timeRange: Round2Fixtures.range(3, 2), layers: [child])
        let moved = group.applyingOffset(Round2Fixtures.time(7))
        let result = TimelineComposition(layers: [moved]).compile()
        XCTAssertEqual(result.renderInstructions.first?.timeRange.start, Round2Fixtures.time(10))
        XCTAssertEqual(result.renderInstructions.first?.layerStates.first?.opacity, 0)
    }
    func testSequentialDestinationClipsUseIdenticalVideoAndAudioTransitionProgress() throws {
        let transition = Transition(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)
        let result = TimelineComposition(layers: [clip(0, 3, 0), clip(0, 1, 1), clip(1, 2, 1)], transitions: [transition]).compile()
        XCTAssertEqual(try opacity(result, level: 1, at: 1.5), 0.75, accuracy: 0.002)
        XCTAssertEqual(try gain(result, level: 1, at: 1.5), 0.75, accuracy: 0.002)
        XCTAssertEqual(result.renderPlan.transitionSegments.count, 2)
    }
    func testAudioAutomationMultipliesWithTransitionEnvelope() throws {
        let a = clip(0, 2, 0)
        a.audioRamps = [.init(startVolume: 0, endVolume: 1, timeRange: Round2Fixtures.range(0, 2))]
        let transition = Transition(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)
        let result = TimelineComposition(layers: [a, clip(0, 2, 1)], transitions: [transition]).compile()
        XCTAssertEqual(try gain(result, level: 0, at: 0.5), 0.1875, accuracy: 0.002)
        let segment = try XCTUnwrap(result.renderPlan.audioMixSegments.first { $0.layerLevel == 0 })
        XCTAssertEqual(segment.volume(at: Round2Fixtures.time(0.5)), 0.1875, accuracy: 0.002)
    }
    func testScheduledEffectsSkipInactiveSegmentsAndAllowReverseSeeks() throws {
        let calls = Round2LockedValues()
        let layers = (0..<128).map { index in
            EffectLayer(timeRange: Round2Fixtures.range(Double(index), 1),
                source: EffectSource(makeProcessor: { ClosureFrameProcessor { frame, completion in calls.append(index); completion(.success(frame)) } }))
        }
        let compiled = TimelineComposition(layers: layers).compile()
        let chain = compiled.makeProcessorChain()
        for time in [0.5, 100.5, 1.5, -1] {
            let done = expectation(description: "只执行活动效果")
            chain.consume(try Round2Fixtures.frame(0, time: time)) { result in if case .failure(let error) = result { XCTFail(String(describing: error)) }; done.fulfill() }
            wait(for: [done], timeout: 3)
        }
        XCTAssertEqual(calls.values, [0, 100, 1])
    }
    func testBlendingContextIsLazyAndSharedAcrossEffectSegments() throws {
        let layers = (0..<2).map { EffectLayer(timeRange: Round2Fixtures.range(Double($0), 1), processor: PassthroughFrameProcessor(), intensity: 0.5) }
        let processors = TimelineComposition(layers: layers).compile().timelineProcessors
        let first = try XCTUnwrap(processors[0] as? TimelineEffectProcessor)
        let second = try XCTUnwrap(processors[1] as? TimelineEffectProcessor)
        XCTAssertEqual(first.blendContextCount, 0); XCTAssertEqual(second.blendContextCount, 0)
        for (i, processor) in processors.enumerated() {
            let done = expectation(description: "共享混合资源")
            processor.process(try Round2Fixtures.frame(i, time: Double(i) + 0.5)) { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }; done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        XCTAssertEqual(first.blendContextCount, 1); XCTAssertEqual(second.blendContextCount, 1)
    }
    func testNegativeDestinationIsDiagnosedWithoutInvalidVideoInstructions() {
        let layer = clip(-1, 1, 0)
        let result = TimelineComposition(layers: [layer]).compile()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.videoComposition.instructions.isEmpty)
    }
    func testOutputCanvasSurvivesRealExportAndValidatorRejectsWrongSize() throws {
        let source = try Round2Fixtures.movie(self); let output = Round2Fixtures.url()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }
        let asset = AVURLAsset(url: source)
        let range = CMTimeRange(start: .zero, duration: asset.duration)
        let result = TimelineComposition(renderSize: CGSize(width: 32, height: 48),
            layers: [ClipLayer(asset: asset, timeRange: range, sourceTimeRange: range)]).compile()
        let job = result.makeExportJob(outputURL: output)
        let done = expectation(description: "画布合同产物")
        job.export { value in if case .failure(let error) = value { XCTFail(String(describing: error)) }; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(job.status, .completed)
        let actual = try VideoAssetProfileInspector().inspect(AVURLAsset(url: output))
        XCTAssertEqual(actual.presentationSize, CGSize(width: 32, height: 48))
        XCTAssertThrowsError(try VideoArtifactValidator.validate(url: output,
            expectation: .init(sourceDuration: asset.duration, expectsAudio: false, expectedVideoSize: CGSize(width: 64, height: 64))))
    }
}
#endif
