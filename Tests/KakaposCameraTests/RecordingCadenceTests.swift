//
//  RecordingCadenceTests.swift
//  KakaposCameraTests
//
//  Created by Condy on 2026/11/16.
//

import AVFoundation
import CoreVideo
import KakaposMediaCore
import XCTest
@testable import KakaposCamera

final class RecordingCadenceTests: XCTestCase {
    func testFixedRateLongClockAndCodableRoundTrip() throws {
        for fps in [24, 30, 60] {
            var value = RecordingCadence()
            for index in 0..<(fps * 600) {
                value.recordVideo(seconds: Double(index) / Double(fps), duration: 1 / Double(fps))
            }
            XCTAssertEqual(value.videoFrameCount, fps * 600)
            XCTAssertEqual(value.effectiveVideoFrameRate ?? 0, Double(fps), accuracy: 0.000001)
            XCTAssertEqual(value.maximumVideoGapSeconds, 1 / Double(fps), accuracy: 0.000001)
            XCTAssertEqual(value.nonMonotonicVideoFrames, 0)
            XCTAssertEqual(try JSONDecoder().decode(RecordingCadence.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testVariableRateDropsAndAudioOffsetsHaveIndependentMeaning() {
        var value = RecordingCadence()
        for time in [0.0, 0.02, 0.04, 0.14, 0.19] { value.recordVideo(seconds: time, duration: 0.04) }
        value.recordAudio(seconds: 0.01, duration: 0.2)
        value.recordDrop(audio: false)
        value.recordDrop(audio: false)
        value.recordDrop(audio: true)
        XCTAssertEqual(value.maximumVideoGapSeconds, 0.1, accuracy: 0.000001)
        XCTAssertEqual(value.effectiveVideoFrameRate ?? 0, 4 / 0.19, accuracy: 0.000001)
        XCTAssertEqual(value.audioVideoStartOffsetSeconds ?? 0, 0.01, accuracy: 0.000001)
        XCTAssertEqual(value.audioVideoEndOffsetSeconds ?? 0, -0.02, accuracy: 0.000001)
        XCTAssertEqual(value.droppedVideoFrames, 2)
        XCTAssertEqual(value.droppedAudioBuffers, 1)
        value.recordVideo(seconds: .infinity, duration: 1)
        value.recordAudio(seconds: .nan, duration: 1)
        XCTAssertEqual(value.videoFrameCount, 5)
        XCTAssertEqual(value.audioSampleBufferCount, 1)
        value.recordVideo(seconds: 0.19, duration: 0.04)
        XCTAssertEqual(value.nonMonotonicVideoFrames, 1)
    }

    func testUnknownDurationDoesNotInventAnEndOffset() {
        var value = RecordingCadence()
        value.recordVideo(seconds: 0, duration: 0)
        value.recordAudio(seconds: 0, duration: 0.02)
        XCTAssertNil(value.audioVideoEndOffsetSeconds)
        value.recordVideo(seconds: 0.02, duration: 0.02)
        XCTAssertEqual(value.audioVideoEndOffsetSeconds ?? 1, -0.02, accuracy: 0.000001)
    }

    func testRecorderCountsRealAdmissionPressureAndAttachesSnapshot() throws {
        let url = outputURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = try RecorderSink(outputURL: url, configuration: .init(includesAudio: false))
        let buffer = try pixelBuffer()
        let completed = expectation(description: "有界录制入口完成")
        completed.expectedFulfillmentCount = 128
        for index in 0..<128 {
            sink.consume(PixelBufferFrame(pixelBuffer: buffer,
                metadata: .init(presentationTime: CMTime(value: Int64(index), timescale: 60), duration: CMTime(value: 1, timescale: 60)))) { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
                completed.fulfill()
            }
        }
        wait(for: [completed], timeout: 10)
        let value = sink.recordingCadence
        XCTAssertGreaterThan(value.videoFrameCount, 0)
        XCTAssertGreaterThan(value.droppedVideoFrames, 0)
        XCTAssertEqual(value.videoFrameCount + value.droppedVideoFrames, 128)
        let finished = expectation(description: "录制摘要随结果交付")
        sink.finishRecording { result in
            switch result {
            case .success(let clip): XCTAssertEqual(clip.recordingCadence, value)
            case .failure(let error): XCTFail(String(describing: error))
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
    }

    func testTwelveSecondFileCadenceMatchesCompressedSamples() async throws {
        let url = outputURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = try RecorderSink(outputURL: url, configuration: .init(includesAudio: false))
        let buffer = try pixelBuffer()
        for index in 0..<720 {
            let deadline = Date().addingTimeInterval(2)
            while !sink._videoInputReadyForTesting && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
            let done = expectation(description: "连续写入")
            sink.consume(PixelBufferFrame(pixelBuffer: buffer,
                metadata: .init(presentationTime: CMTime(value: Int64(index), timescale: 60), duration: CMTime(value: 1, timescale: 60)))) { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
                done.fulfill()
            }
            await fulfillment(of: [done], timeout: 3)
        }
        let finished = expectation(description: "长片段收尾")
        sink.finishRecording { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        let value = sink.recordingCadence
        XCTAssertEqual(value.videoFrameCount, 720)
        XCTAssertEqual(value.droppedVideoFrames, 0)
        XCTAssertEqual(value.effectiveVideoFrameRate ?? 0, 60, accuracy: 0.000001)
        XCTAssertEqual(value.maximumVideoGapSeconds, 1.0 / 60, accuracy: 0.000001)
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while let sample = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(sample) }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(count, value.videoFrameCount)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 12, accuracy: 0.05)
    }

    func testEighteenFpsRecordingPreservesClockAndFrameCount() async throws {
        let url = outputURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = try RecorderSink(outputURL: url, configuration: .init(includesAudio: false))
        let buffer = try pixelBuffer()
        let duration = try CameraFrameRateRange(minimumFramesPerSecond: 18, maximumFramesPerSecond: 18).frameDurations().minimum
        for index in 0..<36 {
            let deadline = Date().addingTimeInterval(2)
            while !sink._videoInputReadyForTesting && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
            let done = expectation(description: "18fps帧完成")
            sink.consume(PixelBufferFrame(pixelBuffer: buffer, metadata: .init(
                presentationTime: CMTimeMultiply(duration, multiplier: Int32(index)), duration: duration))) { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
                done.fulfill()
            }
            await fulfillment(of: [done], timeout: 3)
        }
        let finished = expectation(description: "18fps收尾")
        sink.finishRecording { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertEqual(sink.recordingCadence.videoFrameCount, 36)
        XCTAssertEqual(sink.recordingCadence.effectiveVideoFrameRate ?? 0, 18, accuracy: 0.000001)
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetOutputPresentationTimeStamp(sample)
            if CMSampleBufferGetNumSamples(sample) == 0 {
                XCTAssertNil(CMSampleBufferGetDataBuffer(sample))
                continue
            }
            XCTAssertTrue(time.isNumeric)
            times.append(time)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(times.count, 36)
        times.sort { $0 < $1 }
        let tolerance = 1 / Double(max(1, track.naturalTimeScale))
        let origin = try XCTUnwrap(times.first)
        // 原始压缩流允许编码重排起点；帧节奏以相对呈现时间和容器精度验收。
        for (index, time) in times.enumerated() {
            XCTAssertEqual((time - origin).seconds, Double(index) / 18, accuracy: 2 * tolerance)
        }
        let fileDuration = try await asset.load(.duration)
        XCTAssertEqual(fileDuration.seconds, 2, accuracy: 0.06)
    }

    private func outputURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4") }
    private func pixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let value = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(value, [])
        memset(CVPixelBufferGetBaseAddress(value), 128, CVPixelBufferGetBytesPerRow(value) * 48)
        CVPixelBufferUnlockBaseAddress(value, [])
        return value
    }
}
