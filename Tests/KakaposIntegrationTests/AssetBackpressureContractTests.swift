//
//  AssetBackpressureContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

#if os(macOS)
    import AVFoundation
    import XCTest
    @testable import KakaposMediaCore
    @testable import KakaposVideo

    final class AssetBackpressureContractTests: XCTestCase {
        func testSlowPipelineDeliversEverySampleWithinSourceCapacity() throws {
            let url = fixtureURL()
            let expectedCount = try sampleCount(url)
            let source = AssetSource(asset: AVAsset(url: url))
            let pressure = PressureState()
            let processor = ClosureFrameProcessor { frame, completion in
                pressure.begin()
                let transfer = Transfer(value: (frame, completion))
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(2)) {
                    pressure.end()
                    transfer.value.1(.success(transfer.value.0))
                }
            }
            var indices: [Int64] = []
            let sink = PixelBufferSink { frame in
                if let index = frame.metadata.frameIndex { indices.append(index) }
            }
            let done = expectation(description: "无损有界管线结束")
            let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
            pipeline.completionHandler = { done.fulfill() }
            pipeline.errorHandler = { error in
                XCTFail("管线失败：\(error)")
                done.fulfill()
            }
            pipeline.start()
            wait(for: [done], timeout: 15)
            XCTAssertEqual(indices.count, expectedCount)
            XCTAssertEqual(indices.sorted(), Array(1...Int64(expectedCount)))
            XCTAssertLessThanOrEqual(pressure.peak, 2)
            XCTAssertEqual(source.sourceSnapshot.details["inFlightFrames"], "0")
            XCTAssertEqual(source.sourceSnapshot.details["peakInFlightFrames"], "2")
        }

        private func fixtureURL() -> URL {
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("KakaposExamples/IMG_3156.MOV")
        }

        private func sampleCount(_ url: URL) throws -> Int {
            let asset = AVAsset(url: url)
            let reader = try AVAssetReader(asset: asset)
            var outputs: [AVAssetReaderOutput] = []
            let selectedTracks = [asset.tracks(withMediaType: .video).first, asset.tracks(withMediaType: .audio).first].compactMap { $0 }
            for track in selectedTracks {
                let settings: [String: Any]? =
                    track.mediaType == .video
                    ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : nil
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                if reader.canAdd(output) {
                    reader.add(output)
                    outputs.append(output)
                }
            }
            XCTAssertTrue(reader.startReading())
            var total = 0
            for output in outputs {
                while output.copyNextSampleBuffer() != nil { total += 1 }
            }
            return total
        }
    }

    private struct Transfer<Value>: @unchecked Sendable { let value: Value }

    private final class PressureState: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private var maximum = 0
        var peak: Int {
            lock.lock()
            defer { lock.unlock() }
            return maximum
        }
        func begin() {
            lock.lock()
            active += 1
            maximum = max(maximum, active)
            lock.unlock()
        }
        func end() {
            lock.lock()
            active -= 1
            lock.unlock()
        }
    }
#endif
