import XCTest
import AVFoundation
import AudioToolbox
import CoreVideo
@testable import Kakapos
@testable import KakaposMediaCore
@testable import KakaposCamera

final class RecorderSinkRegressionTests: XCTestCase {

    func testFirstVideoFrameRegistersInputBeforeStartingWriter() throws {
        let outputURL = makeOutputURL()
        let sink = try RecorderSink(outputURL: outputURL)
        let frame = PixelBufferFrame(
            pixelBuffer: try makePixelBuffer(),
            metadata: FrameMetadata(presentationTime: .zero)
        )
        let appended = expectation(description: "first video frame appended")
        let finished = expectation(description: "recording finished")

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("First frame should start a valid writer session: \(error)")
            }
            appended.fulfill()
        }
        wait(for: [appended], timeout: 2)

        sink.finishRecording { result in
            if case .failure(let error) = result {
                XCTFail("A recording with its first video frame must finish: \(error)")
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)

        XCTAssertEqual(sink.state, .finished)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testFinishWithoutFramesFailsClosed() throws {
        let outputURL = makeOutputURL()
        let sink = try RecorderSink(outputURL: outputURL)
        let finished = expectation(description: "empty recording rejected")

        sink.finishRecording { result in
            switch result {
            case .success:
                XCTFail("Recorder must not create a success result without media")
            case .failure(let error as RecorderSink.RecorderError):
                XCTAssertEqual(error.localizedDescription, RecorderSink.RecorderError.noRecordedMedia.localizedDescription)
            case .failure(let error):
                XCTFail("Unexpected empty-recording error: \(error)")
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(sink.state, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testLateFramesAfterCancelAndFinishAreIgnored() throws {
        let pixelBuffer = try makePixelBuffer()
        let first = PixelBufferFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let late = PixelBufferFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30))
        )

        let cancelledSink = try RecorderSink(outputURL: makeOutputURL())
        let cancelledFirstFrame = expectation(description: "cancelled sink first frame")
        cancelledSink.consume(first) { _ in cancelledFirstFrame.fulfill() }
        wait(for: [cancelledFirstFrame], timeout: 2)
        let cancelled = expectation(description: "cancelled sink enters cancellation state")
        cancelledSink.stateChangedHandler = { state in
            if state == .cancelled {
                cancelled.fulfill()
            }
        }
        cancelledSink.cancel()
        wait(for: [cancelled], timeout: 2)
        let cancellation = expectation(description: "cancelled sink ignores late frame")
        cancelledSink.consume(late) { result in
            if case .failure(let error) = result {
                XCTFail("Late frame after cancellation should be ignored: \(error)")
            }
            cancellation.fulfill()
        }
        wait(for: [cancellation], timeout: 2)
        XCTAssertEqual(cancelledSink.state, .cancelled)

        let finishedSink = try RecorderSink(outputURL: makeOutputURL())
        let finishedFirstFrame = expectation(description: "finished sink first frame")
        finishedSink.consume(first) { _ in finishedFirstFrame.fulfill() }
        wait(for: [finishedFirstFrame], timeout: 2)
        let finished = expectation(description: "finished sink completes")
        finishedSink.finishRecording { result in
            if case .failure(let error) = result {
                XCTFail("Recording should finish before testing late frames: \(error)")
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)

        let lateAfterFinish = expectation(description: "finished sink ignores late frame")
        finishedSink.consume(late) { result in
            if case .failure(let error) = result {
                XCTFail("Late frame after finish should be ignored: \(error)")
            }
            lateAfterFinish.fulfill()
        }
        wait(for: [lateAfterFinish], timeout: 2)
        XCTAssertEqual(finishedSink.state, .finished)
    }

    func testVideoFirstRecordingAcceptsLaterAudioWhenConfigured() async throws {
        let outputURL = makeOutputURL()
        let sink = try RecorderSink(
            outputURL: outputURL,
            configuration: .init(includesAudio: true)
        )
        let pixelBuffer = try makePixelBuffer()
        let videoFrame = PixelBufferFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero)
        )
        let audioFrame = SampleBufferFrame(
            sampleBuffer: try makeAudioSampleBuffer(at: CMTime(value: 1, timescale: 30))
        )
        let consumed = expectation(description: "video and later audio consumed")
        consumed.expectedFulfillmentCount = 2

        sink.consume(videoFrame) { result in
            if case .failure(let error) = result {
                XCTFail("Video-first frame should not lock out the configured audio input: \(error)")
            }
            consumed.fulfill()
        }
        sink.consume(audioFrame) { result in
            if case .failure(let error) = result {
                XCTFail("Later audio should use the input registered before writing started: \(error)")
            }
            consumed.fulfill()
        }
        await fulfillment(of: [consumed], timeout: 2)

        let finished = expectation(description: "audio recording finished")
        sink.finishRecording { result in
            if case .failure(let error) = result {
                XCTFail("Audio recording should finish successfully: \(error)")
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)

        XCTAssertEqual(sink.state, .finished)
        let audioTracks = try await AVAsset(url: outputURL).loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)
    }

    func testRepeatedFinishCallsShareOneTerminalResult() throws {
        let sink = try RecorderSink(outputURL: makeOutputURL())
        let firstFrame = expectation(description: "first frame")
        sink.consume(
            PixelBufferFrame(
                pixelBuffer: try makePixelBuffer(),
                metadata: FrameMetadata(presentationTime: .zero)
            )
        ) { _ in firstFrame.fulfill() }
        wait(for: [firstFrame], timeout: 2)

        let finished = expectation(description: "both finish callers resolved")
        finished.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            sink.finishRecording { result in
                if case .failure(let error) = result {
                    XCTFail("Repeated finish callers should share the same success: \(error)")
                }
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(sink.state, .finished)
    }

    func testCancelDuringFinishKeepsCancelledTerminalState() throws {
        let sink = try RecorderSink(outputURL: makeOutputURL())
        let firstFrame = expectation(description: "first frame")
        sink.consume(
            PixelBufferFrame(
                pixelBuffer: try makePixelBuffer(),
                metadata: FrameMetadata(presentationTime: .zero)
            )
        ) { _ in firstFrame.fulfill() }
        wait(for: [firstFrame], timeout: 2)

        let finishCallbacks = expectation(description: "finish callers cancelled exactly once")
        finishCallbacks.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            sink.finishRecording { result in
                if case .success = result {
                    XCTFail("Cancellation during finish must not publish a successful artifact")
                }
                finishCallbacks.fulfill()
            }
        }
        sink.cancel()

        wait(for: [finishCallbacks], timeout: 5)
        XCTAssertEqual(sink.state, .cancelled)
        XCTAssertNil(sink.recordedClip)
    }

    private func makeOutputURL() -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: outputURL)
        }
        return outputURL
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            32,
            32,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "RecorderSinkRegressionTests", code: Int(status))
        }
        return pixelBuffer
    }

    private func makeAudioSampleBuffer(at presentationTime: CMTime) throws -> CMSampleBuffer {
        let sampleRate: Float64 = 44_100
        let sampleCount: CMItemCount = 1_024
        let bytesPerSample = MemoryLayout<Int16>.size
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerSample),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NSError(domain: "RecorderSinkRegressionTests.AudioFormat", code: Int(formatStatus))
        }

        let dataLength = Int(sampleCount) * bytesPerSample
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw NSError(domain: "RecorderSinkRegressionTests.AudioBlock", code: Int(blockStatus))
        }

        let silence = [UInt8](repeating: 0, count: dataLength)
        let replaceStatus = silence.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataLength
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw NSError(domain: "RecorderSinkRegressionTests.AudioData", code: Int(replaceStatus))
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerSample
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw NSError(domain: "RecorderSinkRegressionTests.AudioSample", code: Int(sampleStatus))
        }
        return sampleBuffer
    }
}
