//
//  TimelineEffectContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import AVFoundation
import CoreImage
import CoreVideo
import XCTest

@testable import KakaposMediaCore
@testable import KakaposTimeline

final class TimelineEffectContractTests: XCTestCase {
    func testEffectUsesPresentationTimeWithHalfOpenRange() throws {
        let calls = LockedInt()
        let effect = EffectLayer(
            timeRange: CMTimeRange(
                start: CMTime(seconds: 1, preferredTimescale: 30), duration: CMTime(seconds: 1, preferredTimescale: 30)),
            source: EffectSource(makeProcessor: { CountingProcessor(calls: calls) })
        )
        let compiled = TimelinePipeline(layers: [effect]).compile()
        let processor = try XCTUnwrap(compiled.timelineProcessors.first)

        try process(processor, at: 0.5)
        try process(processor, at: 1)
        try process(processor, at: 1.99)
        try process(processor, at: 2)

        XCTAssertEqual(calls.value, 2)
    }

    func testEffectProcessorsRunInLayerOrder() throws {
        let order = LockedArray<Int>()
        let first = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 30)),
            source: EffectSource(makeProcessor: { MarkerProcessor(marker: 2, order: order) }),
            layerLevel: 2
        )
        let second = EffectLayer(
            timeRange: first.timeRange,
            source: EffectSource(makeProcessor: { MarkerProcessor(marker: 1, order: order) }),
            layerLevel: 1
        )

        let compiled = TimelinePipeline(layers: [first, second]).compile()
        for processor in compiled.timelineProcessors {
            try process(processor, at: 0.5)
        }

        XCTAssertEqual(order.values, [1, 2])
    }

    func testEffectsWithEqualLayerLevelKeepInsertionOrder() throws {
        let order = LockedArray<Int>()
        let first = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity),
            source: EffectSource(makeProcessor: { MarkerProcessor(marker: 1, order: order) }),
            layerLevel: 0
        )
        let second = EffectLayer(
            timeRange: first.timeRange,
            source: EffectSource(makeProcessor: { MarkerProcessor(marker: 2, order: order) }),
            layerLevel: 0
        )
        let processors = TimelinePipeline(layers: [first, second]).compile().timelineProcessors
        for processor in processors { try process(processor, at: 0.5) }
        XCTAssertEqual(order.values, [1, 2])
    }

    func testHalfIntensityBlendsInLinearLight() throws {
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity),
            source: EffectSource(makeProcessor: { SolidWhiteProcessor() }, intensity: 0.5)
        )
        let processor = try XCTUnwrap(TimelinePipeline(layers: [effect]).compile().timelineProcessors.first)
        let input = try makeBuffer(fill: 0)
        let expectation = expectation(description: "blend")
        processor.process(PixelBufferFrame(pixelBuffer: input, metadata: FrameMetadata(presentationTime: .zero))) {
            result in
            guard case .success(let frame) = result, let output = extractPixelBuffer(frame) else {
                XCTFail("blend failed")
                expectation.fulfill()
                return
            }
            CVPixelBufferLockBaseAddress(output, .readOnly)
            let value =
                CVPixelBufferGetBaseAddress(output).map { Int($0.assumingMemoryBound(to: UInt8.self).pointee) } ?? -1
            CVPixelBufferUnlockBaseAddress(output, .readOnly)
            XCTAssertGreaterThan(value, 170)
            XCTAssertLessThan(value, 205)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testProcessorAndIntensityMutationRequireRecompile() {
        let first = PassthroughFrameProcessor()
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity), processor: first, intensity: 0.25)
        let pipeline = TimelinePipeline(layers: [effect])
        let before = pipeline.compile()
        let replacement = PassthroughFrameProcessor()
        effect.processor = replacement
        effect.intensity = 0.75
        let after = pipeline.compile()

        XCTAssertEqual(before.renderPlan.processorSegments.first?.source.intensity, 0.25)
        XCTAssertEqual(after.renderPlan.processorSegments.first?.source.intensity, 0.75)
        XCTAssertFalse(before.timelineProcessors[0] as AnyObject === (after.timelineProcessors[0] as AnyObject))
    }

    func testCompilationSnapshotDoesNotChangeAfterLayerMutation() {
        let pipeline = TimelinePipeline()
        let compiled = pipeline.compile()
        pipeline.addLayer(EffectLayer(timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity)))

        XCTAssertEqual(compiled.renderPlan.processorSegments.count, 0)
        XCTAssertEqual(pipeline.compile().renderPlan.processorSegments.count, 1)
    }

    func testNonEmptyVideoProcessorsOverrideTimelineEffects() {
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity), processor: PassthroughFrameProcessor())
        let replacement = PassthroughFrameProcessor()
        let job = TimelinePipeline(layers: [effect]).makeExportJob(
            outputURL: temporaryURL(), videoProcessors: [replacement])

        XCTAssertEqual(job.snapshot.processorCount, 1)
    }

    func testFactoryCreatesFreshProcessorInstances() {
        let factory = EffectSource(makeProcessor: { PassthroughFrameProcessor() })
        let first = EffectLayer(timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity), source: factory)
        let second = EffectLayer(timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity), source: factory)
        let compiled = TimelinePipeline(layers: [first, second]).compile()
        let processors = compiled.timelineProcessors

        XCTAssertEqual(processors.count, 2)
        XCTAssertFalse(processors[0] as AnyObject === (processors[1] as AnyObject))
    }

    func testEffectIntensityKeyframeIsInterpolatedInRenderPlan() {
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 30)),
            intensity: 0,
            layerLevel: 0
        )
        effect.keyframes = [
            KeyframeAnimation(
                keyPath: "intensity",
                values: [0, 1],
                keyTimes: [.zero, CMTime(seconds: 2, preferredTimescale: 30)]
            )
        ]
        let plan = TimelinePipeline(layers: [effect]).compile().renderPlan
        let segment = plan.processorSegments[0]

        XCTAssertEqual(segment.intensity(at: CMTime(seconds: 0.5, preferredTimescale: 30)), 0.25, accuracy: 0.001)
        XCTAssertEqual(segment.intensity(at: CMTime(seconds: 1, preferredTimescale: 30)), 0.5, accuracy: 0.001)
    }

    private func process(_ processor: FrameProcessor, at seconds: Double) throws {
        let expectation = expectation(description: "processor")
        let buffer = try makeBuffer()
        processor.process(
            PixelBufferFrame(
                pixelBuffer: buffer,
                metadata: FrameMetadata(presentationTime: CMTime(seconds: seconds, preferredTimescale: 30))
            )
        ) { result in
            if case .failure(let error) = result {
                XCTFail("processor failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func makeBuffer(fill: UInt8 = 0) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            2,
            2,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw NSError(domain: "TimelineEffectContractTests", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(fill), CVPixelBufferGetDataSize(buffer))
            for y in 0..<2 {
                for x in 0..<2 {
                    base.assumingMemoryBound(to: UInt8.self)[y * CVPixelBufferGetBytesPerRow(buffer) + x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }
}

private final class LockedInt {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedArray<Element> {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Element) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private struct CountingProcessor: FrameProcessor {
    let calls: LockedInt

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        calls.increment()
        completion(.success(frame))
    }
}

private struct MarkerProcessor: FrameProcessor {
    let marker: Int
    let order: LockedArray<Int>

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        order.append(marker)
        completion(.success(frame))
    }
}

private struct SolidWhiteProcessor: FrameProcessor {
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        guard let input = extractPixelBuffer(frame), let output = try? makeWhiteBufferLike(input) else {
            completion(.failure(NSError(domain: "TimelineEffectContractTests", code: 1)))
            return
        }
        completion(.success(PixelBufferFrame(pixelBuffer: output, metadata: frame.metadata)))
    }

    private func makeWhiteBufferLike(_ input: CVPixelBuffer) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, CVPixelBufferGetWidth(input), CVPixelBufferGetHeight(input), kCVPixelFormatType_32BGRA, nil, &output)
        guard status == kCVReturnSuccess, let output else {
            throw NSError(domain: "TimelineEffectContractTests", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(output, [])
        if let base = CVPixelBufferGetBaseAddress(output) { memset(base, 255, CVPixelBufferGetDataSize(output)) }
        CVPixelBufferUnlockBaseAddress(output, [])
        return output
    }
}
