//
//  TimelineCompilationContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/11/6.
//

import AVFoundation
import CoreGraphics
import XCTest
@testable import KakaposMediaCore
@testable import KakaposTimeline

final class TimelineCompilationContractTests: XCTestCase {
    func testCompilerKeepsMixedLayerTieOrder() throws {
        let range = timeRange(0, 2)
        let image = ImageLayer(image: try makeImage(), timeRange: range)
        let text = TextLayer(attributedText: NSAttributedString(string: "文字"), frame: .zero, timeRange: range)
        let first = EffectLayer(timeRange: range, processor: CompilationMarker(1))
        let second = EffectLayer(timeRange: range, processor: CompilationMarker(2))
        let compiled = TimelineComposition(layers: [first, text, second, image]).compile()

        let instruction = try XCTUnwrap(compiled.renderInstructions.first)
        XCTAssertEqual(instruction.layerStates.map(\.kind), [.image, .text, .effect, .effect])
        XCTAssertEqual(instruction.processors.compactMap { ($0 as? CompilationMarker)?.id }, [1, 2])
        XCTAssertEqual(compiled.renderPlan.visualIntervals.count, 1)
    }

    func testEqualCutPointsKeepOriginalTimeRepresentation() throws {
        let imageRange = CMTimeRange(start: CMTime(value: 30, timescale: 30), end: CMTime(value: 60, timescale: 30))
        let image = ImageLayer(image: try makeImage(), timeRange: imageRange, layerLevel: 5)
        let effect = EffectLayer(timeRange: timeRange(1, 2), layerLevel: 0)
        let compiled = TimelineComposition(layers: [effect, image]).compile()
        let instruction = try XCTUnwrap(compiled.renderInstructions.first)

        XCTAssertEqual(instruction.timeRange.start.value, 30)
        XCTAssertEqual(instruction.timeRange.start.timescale, 30)
        XCTAssertEqual(instruction.timeRange.duration.value, 30)
        XCTAssertEqual(instruction.timeRange.duration.timescale, 30)
        XCTAssertEqual(instruction.layerLevels, [0, 5])
    }

    func testCompilerKeepsOverlapBoundariesAndAnimatedState() throws {
        let first = EffectLayer(timeRange: timeRange(0, 3), processor: CompilationMarker(10), layerLevel: 1)
        first.keyframes = [
            KeyframeAnimation(keyPath: "opacity", values: [0, 1], keyTimes: [.zero, time(4)]),
            KeyframeAnimation(keyPath: "translation.x", values: [0, 40], keyTimes: [.zero, time(4)])
        ]
        let second = EffectLayer(timeRange: timeRange(1, 2), processor: CompilationMarker(20), layerLevel: -1)
        let third = EffectLayer(timeRange: timeRange(1, 4), processor: CompilationMarker(30), layerLevel: 1)
        let compiled = TimelineComposition(layers: [first, third, second]).compile()
        let expected = [[10], [20, 10, 30], [10, 30], [30]]

        XCTAssertEqual(compiled.renderInstructions.map { $0.timeRange.start.seconds }, [0, 1, 2, 3])
        XCTAssertEqual(compiled.renderInstructions.map { $0.timeRange.duration.seconds }, [1, 1, 1, 1])
        XCTAssertEqual(compiled.renderInstructions.map { $0.processors.compactMap { ($0 as? CompilationMarker)?.id } }, expected)
        XCTAssertEqual(compiled.renderPlan.visualIntervals.map {
            $0.processorSegments.compactMap { ($0.source.processor as? CompilationMarker)?.id }
        }, expected)
        let animated = try XCTUnwrap(compiled.renderInstructions[2].layerStates.first)
        XCTAssertEqual(animated.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(animated.transform.tx, 20, accuracy: 0.0001)
    }

    func testRenderPlanKeepsAllSegmentOrdersForOutOfOrderIntervals() throws {
        let fixture = try mixedFixture()
        let ranges = [timeRange(2, 3), timeRange(0, 1), timeRange(1, 2), timeRange(4, 5)]
        let plan = TimelineRenderPlanBuilder(transitions: []).makePlan(
            renderInstructions: ranges.map(instruction),
            resolvedLayers: fixture.layers,
            videoAllocation: fixture.allocation,
            audioAllocation: [:]
        )
        let expected = [[3, 1], [2], [2, 3, 1], []]

        XCTAssertEqual(plan.visualIntervals.map(\.timeRange), ranges)
        XCTAssertEqual(plan.visualIntervals.map { $0.assetSegments.compactMap(\.compositionTrackID).map(Int.init) }, expected)
        XCTAssertEqual(plan.visualIntervals.map { $0.imageSegments.map { Int($0.opacity) } }, expected)
        XCTAssertEqual(plan.visualIntervals.map { $0.textSegments.compactMap { Int($0.source.attributedText.string) } }, expected)
        XCTAssertEqual(plan.visualIntervals.map { $0.processorSegments.map { Int($0.source.intensity) } }, expected)
        // 顶层片段维持原有顺序；区间内的显示顺序不能反向修改它们。
        XCTAssertEqual(plan.assetSegments.compactMap(\.compositionTrackID), [1, 2, 3])
        XCTAssertEqual(plan.imageSegments.map { Int($0.opacity) }, [1, 2, 3])
        XCTAssertEqual(plan.processorSegments.map { Int($0.source.intensity) }, [1, 2, 3])
    }

    func testTransitionsKeepTieSelectionAndInputOrder() throws {
        let fixture = try mixedFixture()
        let transitions = [
            Transition(timeRange: timeRange(2, 3)),
            Transition(timeRange: timeRange(1, 2)),
            Transition(timeRange: timeRange(1, 2), sourceLayerLevel: 2, destinationLayerLevel: 0)
        ]
        let plan = TimelineRenderPlanBuilder(transitions: transitions).makePlan(
            renderInstructions: [instruction(timeRange(1, 3))],
            resolvedLayers: fixture.layers,
            videoAllocation: fixture.allocation,
            audioAllocation: [:]
        )

        XCTAssertEqual(plan.transitionSegments.compactMap(\.sourceTrackID), [3, 2, 1])
        XCTAssertEqual(plan.transitionSegments.compactMap(\.destinationTrackID), [1, 3, 2])
        XCTAssertEqual(plan.transitionSegments.map(\.timeRange), transitions.map(\.timeRange))
        XCTAssertEqual(plan.visualIntervals[0].transitionSegments.compactMap(\.sourceTrackID), [3, 2, 1])
    }

    func testEmptyAndInfiniteEffectRangesRetainTheirExistingBoundaries() {
        let infinite = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity), processor: CompilationMarker(1))
        let finite = EffectLayer(timeRange: timeRange(1, 2), processor: CompilationMarker(2), layerLevel: -1)
        let empty = EffectLayer(timeRange: timeRange(1, 1), processor: CompilationMarker(3))
        let compiled = TimelineComposition(layers: [infinite, empty, finite]).compile()

        XCTAssertEqual(compiled.renderInstructions.map { $0.processors.compactMap { ($0 as? CompilationMarker)?.id } }, [[1], [2, 1], [1]])
        XCTAssertEqual(compiled.renderInstructions.last?.timeRange.end, .positiveInfinity)
        XCTAssertEqual(TimelineComposition().compile().renderPlan.visualIntervals.count, 0)
    }

    func testDenseTimelineCompilationPerformance() {
        let composition = denseComposition()
        measure {
            let compiled = composition.compile()
            XCTAssertEqual(compiled.renderInstructions.count, 359)
            XCTAssertEqual(compiled.renderPlan.visualIntervals.count, 359)
        }
    }

    func testDenseRenderPlanPerformance() {
        let compiled = denseComposition().compile()
        let builder = TimelineRenderPlanBuilder(transitions: [])
        measure {
            let plan = builder.makePlan(
                renderInstructions: compiled.renderInstructions,
                resolvedLayers: compiled.resolvedLayers,
                videoAllocation: [:],
                audioAllocation: [:]
            )
            XCTAssertEqual(plan.visualIntervals.count, 359)
        }
    }

    private func denseComposition() -> TimelineComposition {
        let layers = (0..<180).map { index in
            EffectLayer(timeRange: timeRange(index, index + 180), intensity: Float(index), layerLevel: (index * 37) % 23)
        }
        return TimelineComposition(layers: layers)
    }

    private func mixedFixture() throws -> (layers: ResolvedTimelineLayers, allocation: [ObjectIdentifier: CMPersistentTrackID]) {
        let ranges = [timeRange(1, 3), timeRange(0, 2), timeRange(1, 4)]
        let levels = [2, 0, 0]
        let image = try makeImage()
        let source = AssetClipSource(asset: AVMutableComposition(), preferredTransform: .identity)
        let clips = (0..<3).map { ClipLayer(source: source, timeRange: ranges[$0], layerLevel: levels[$0]) }
        let images = (0..<3).map { index in
            let layer = ImageLayer(image: image, timeRange: ranges[index], layerLevel: levels[index])
            layer.opacity = Float(index + 1)
            return layer
        }
        let texts = (0..<3).map { index in
            TextLayer(
                attributedText: NSAttributedString(string: String(index + 1)),
                frame: .zero,
                timeRange: ranges[index],
                layerLevel: levels[index]
            )
        }
        let effects = (0..<3).map { EffectLayer(timeRange: ranges[$0], intensity: Float($0 + 1), layerLevel: levels[$0]) }
        let allocation = Dictionary(uniqueKeysWithValues: clips.enumerated().map { (ObjectIdentifier($0.element), CMPersistentTrackID($0.offset + 1)) })
        let layers = ResolvedTimelineLayers(
            videoLayers: clips,
            imageLayers: images,
            textLayers: texts,
            audioLayers: [],
            effectLayers: effects
        )
        return (layers, allocation)
    }

    private func instruction(_ range: CMTimeRange) -> TimelineRenderInstruction {
        TimelineRenderInstruction(
            timeRange: range,
            layerLevels: [],
            sourceTrackIDs: [],
            layerStates: [],
            processors: []
        )
    }

    private func time(_ seconds: Int) -> CMTime { CMTime(value: Int64(seconds), timescale: 1) }
    private func timeRange(_ start: Int, _ end: Int) -> CMTimeRange { CMTimeRange(start: time(start), end: time(end)) }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}

private final class CompilationMarker: FrameProcessor {
    let id: Int
    init(_ id: Int) { self.id = id }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        completion(.success(frame))
    }
}
