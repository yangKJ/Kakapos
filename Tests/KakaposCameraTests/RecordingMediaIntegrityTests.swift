// 作者：Condy
#if os(macOS)
import AudioToolbox
import AVFoundation
import CoreVideo
import XCTest
@testable import KakaposCamera
import KakaposMediaCore
import KakaposTimeline
import KakaposVideo

final class RecordingMediaIntegrityTests: XCTestCase {
    private var files: [URL] = []
    override func tearDown() { files.forEach { try? FileManager.default.removeItem(at: $0) }; super.tearDown() }
    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }
    private func url(_ suffix: String = "mp4") -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + suffix); files.append(value); return value
    }
    private func video(_ seconds: Double, duration: Double = 1.0 / 30) throws -> PixelBufferFrame {
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &value), kCVReturnSuccess)
        let buffer = try XCTUnwrap(value); CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetBytesPerRow(buffer) * 64); CVPixelBufferUnlockBaseAddress(buffer, [])
        return PixelBufferFrame(pixelBuffer: buffer, metadata: .init(presentationTime: time(seconds), duration: time(duration)))
    }
    private func audio(_ seconds: Double) throws -> SampleBufferFrame {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?; var block: CMBlockBuffer?; var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 2048,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 2048, flags: 0, blockBufferOut: &block), noErr)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: try XCTUnwrap(block), offsetIntoDestination: 0, dataLength: 2048)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 44_100), decodeTimeStamp: .invalid)
        var size = 2
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1024,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample), noErr)
        return SampleBufferFrame(sampleBuffer: try XCTUnwrap(sample))
    }
    private func append(_ frame: MediaFrame, to sink: RecorderSink) {
        let end = Date().addingTimeInterval(3)
        while !sink._videoInputReadyForTesting && Date() < end { Thread.sleep(forTimeInterval: 0.001) }
        let done = expectation(description: "帧接收")
        sink.consume(frame) { result in if case .failure(let error) = result { XCTFail("\(error)") }; done.fulfill() }
        wait(for: [done], timeout: 5)
    }
    private func finish(_ sink: RecorderSink) throws -> RecordedClip {
        let done = expectation(description: "真实录制收尾"); var value: RecordedClip?
        sink.finishRecording { result in
            switch result { case .success(let clip): value = clip; case .failure(let error): XCTFail("\(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10); return try XCTUnwrap(value)
    }
    private func count(_ url: URL) throws -> Int {
        let asset = AVURLAsset(url: url); let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(asset.tracks(withMediaType: .video).first), outputSettings: nil)
        reader.add(output); XCTAssertTrue(reader.startReading()); var count = 0
        while let sample = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(sample) }
        XCTAssertEqual(reader.status, .completed); return count
    }
    func testCallbacksCanReadSnapshotPauseResumeAndFinishWithoutDeadlock() throws {
        let sink = try RecorderSink(outputURL: url()); let done = expectation(description: "回调控制完成")
        var controlled = false
        sink.durationChangedHandler = { [weak sink] _ in
            guard let sink, !controlled else { return }; controlled = true
            XCTAssertEqual(sink.snapshot.state, .recording)
            sink.pauseRecording(); XCTAssertEqual(sink.snapshot.state, .paused)
            sink.resumeRecording(); XCTAssertEqual(sink.snapshot.state, .recording)
            sink.finishRecording { result in
                if case .failure(let error) = result { XCTFail("\(error)") }
                XCTAssertEqual(sink.snapshot.state, .finished); done.fulfill()
            }
        }
        append(try video(0), to: sink); wait(for: [done], timeout: 10); XCTAssertTrue(controlled)
    }
    func testRepeatedPauseMatrixPreservesVFRAndNonzeroOrigin() throws {
        for origin in [0.0, 60.0] { for explicit in [false, true] {
            let sink = try RecorderSink(outputURL: url())
            for phase in 0..<3 {
                let raw = origin + Double(phase) * 1.1
                for offset in [0.0, 1.0 / 30, phase == 2 ? 1.0 / 30 + 0.5 : 2.0 / 30] {
                    let before = sink.snapshot.lastPresentationTime
                    append(try video(raw + offset), to: sink)
                    if phase == 2 && offset > 0.5, let before { XCTAssertEqual((sink.snapshot.lastPresentationTime! - before).seconds, 0.5, accuracy: 0.0001) }
                }
                if phase < 2 {
                    if explicit { sink.pauseRecording(at: time(raw + 0.1)) } else { sink.pauseRecording() }
                    XCTAssertGreaterThanOrEqual(sink.snapshot.pausedAt!.seconds, origin)
                    sink.resumeRecording()
                }
            }
            let clip = try finish(sink)
            XCTAssertEqual(sink.recordingCadence.videoFrameCount, 9); XCTAssertEqual(sink.recordingCadence.droppedVideoFrames, 0)
            XCTAssertEqual(clip.duration.seconds, 0.2 + 0.5 + 2.0 / 30, accuracy: 0.0001)
            XCTAssertEqual(AVURLAsset(url: sink.outputURL).duration.seconds, clip.duration.seconds, accuracy: 0.002)
        } }
    }
    func testRecordingSessionClockMatrixDoesNotAccumulateOldOffsets() {
        for origin in [0.0, 60.0] { for pauses in [0, 1, 2, 10] { for fps in [24, 30, 60] { for vfr in [false, true] {
            let session = RecordingSession(); let step = 1.0 / Double(fps); let active = 3 * step + (vfr ? 0.5 : 0)
            var raw = origin
            for phase in 0...pauses {
                if phase > 0 { session.resume(at: time(raw)) }
                for offset in [0.0, step, 2 * step + (vfr ? 0.5 : 0)] { session.markVideoFrame(at: session.normalizedTime(for: time(raw + offset)), duration: time(step)) }
                let end = raw + active
                session.pause(at: time(end)); session.finalizeCurrentClipIfNeeded(preferredEndTime: session.normalizedTime(for: time(end)))
                raw = end + 1.25
            }
            XCTAssertEqual(session.snapshot().totalDuration.seconds, Double(pauses + 1) * active, accuracy: 0.0002)
            XCTAssertEqual(session.clips.count, pauses + 1)
        } } } }
    }
    func testAllFramesAndDurationsSurviveRecordedClipBridge() throws {
        for origin in [0.0, 60.0] { for frames in [1, 2, 30] {
            let sink = try RecorderSink(outputURL: url())
            for index in 0..<frames { append(try video(origin + Double(index) / 30), to: sink) }
            let clip = try finish(sink)
            XCTAssertEqual(clip.duration.seconds, Double(frames) / 30, accuracy: 0.0001)
            XCTAssertEqual(AVURLAsset(url: sink.outputURL).duration.seconds, clip.duration.seconds, accuracy: 0.002)
            XCTAssertNotNil(clip.generatedPreviewImage(at: clip.thumbnailTime ?? .zero))
            let output = url(); let job = try XCTUnwrap(clip.makeExportJob(outputURL: output, renderSize: CGSize(width: 64, height: 64)))
            let done = expectation(description: "录制桥接导出")
            job.export { result in if case .failure(let error) = result { XCTFail("\(error)") }; done.fulfill() }
            wait(for: [done], timeout: 10)
            XCTAssertEqual(try count(sink.outputURL), frames); XCTAssertEqual(try count(output), frames)
        } }
    }
    func testResumeAlignmentPreservesAudioOffsetRegardlessOfArrivalOrder() throws {
        for audioFirst in [true, false] {
            let sink = try RecorderSink(outputURL: url(), configuration: .init(includesAudio: true))
            for phase in 0..<2 {
                let raw = Double(phase) * 10
                let frames: [MediaFrame] = audioFirst ? [try audio(raw + 0.01), try video(raw)] : [try video(raw), try audio(raw + 0.01)]
                for frame in frames { append(frame, to: sink) }
                if phase == 0 { sink.pauseRecording(); sink.resumeRecording() }
            }
            let clip = try finish(sink)
            XCTAssertEqual(sink.recordingCadence.videoFrameCount, 2); XCTAssertEqual(sink.recordingCadence.audioSampleBufferCount, 2)
            XCTAssertEqual(sink.recordingCadence.audioVideoStartOffsetSeconds ?? -1, 0.01, accuracy: 0.0001)
            XCTAssertTrue(clip.containsAudio); XCTAssertTrue(clip.containsVideo)
            XCTAssertEqual(AVURLAsset(url: sink.outputURL).duration.seconds, clip.duration.seconds, accuracy: 0.005)
        }
    }
    func testAudioOnlyDurationIncludesLastBufferAndMaximumDuration() throws {
        let sink = try RecorderSink(outputURL: url("m4a"), fileType: .m4a, configuration: .init(includesVideo: false, includesAudio: true))
        sink.maximumDuration = CMTime(value: 2048, timescale: 44_100)
        append(try audio(60), to: sink); append(try audio(60 + 1024.0 / 44_100), to: sink)
        let clip = try finish(sink)
        XCTAssertEqual(clip.duration.seconds, 2048.0 / 44_100, accuracy: 0.0001)
        XCTAssertEqual(AVURLAsset(url: sink.outputURL).duration.seconds, clip.duration.seconds, accuracy: 0.005)
    }
    func testAudioTailRemainsAvailableToTimelineBridge() throws {
        let sink = try RecorderSink(outputURL: url(), configuration: .init(includesAudio: true))
        append(try video(0), to: sink); append(try audio(0), to: sink)
        append(try video(1.0 / 30), to: sink)
        for index in 1..<6 { append(try audio(Double(index) * 1024 / 44_100), to: sink) }
        let clip = try finish(sink)
        let compiled = try XCTUnwrap(clip.makeTimelinePipeline(renderSize: CGSize(width: 64, height: 64))).compile()
        XCTAssertTrue(compiled.isValid, "\(compiled.diagnostics)")
        XCTAssertGreaterThan(clip.duration.seconds, 2.0 / 30)
        XCTAssertEqual(AVURLAsset(url: sink.outputURL).duration.seconds, clip.duration.seconds, accuracy: 0.005)
    }
    func testControllerEventsAreAuthoritativeAndExactlyOnce() throws {
        let source = ManualCameraSource(); let controller = try CameraRecordingController(source: source, outputURL: url())
        var starts = 0; var finishes = 0; let finished = expectation(description: "真实完成事件")
        controller.eventHandler = { [weak controller] event in
            switch event {
            case .didStart: starts += 1
            case .didFinish:
                finishes += 1; XCTAssertEqual(controller?.state, .finished); XCTAssertNotNil(controller?.recordedClip); finished.fulfill()
            default: break
            }
        }
        controller.start(); controller.start(); XCTAssertEqual(controller.state, .preparing); XCTAssertEqual(starts, 0); XCTAssertEqual(source.starts, 1)
        append(try video(0), to: controller.recorderSink)
        let done = expectation(description: "控制器返回结果")
        controller.stopRecording { result in if case .failure(let error) = result { XCTFail("\(error)") }; done.fulfill() }
        wait(for: [done, finished], timeout: 10); XCTAssertEqual(starts, 1); XCTAssertEqual(finishes, 1)
    }
    func testRecorderReleasesAfterFinishAndCancel() throws {
        for cancelled in [false, true] {
            var sink: RecorderSink? = try RecorderSink(outputURL: url())
            weak var weakSink = sink
            append(try video(0), to: sink!)
            if cancelled {
                sink?.cancel()
                let done = expectation(description: "取消收口")
                sink?.finishRecording { _ in done.fulfill() }; wait(for: [done], timeout: 5)
            } else { _ = try finish(sink!) }
            sink = nil
            let end = Date().addingTimeInterval(2)
            while weakSink != nil && Date() < end { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
            XCTAssertNil(weakSink)
        }
    }
    func testAsynchronousSinkFailureUsesPipelineFailureTerminalOnlyOnce() throws {
        enum Failure: Error { case injected }
        let source = ManualCameraSource(); let pipeline = try RecordingPipeline(source: source, outputURL: url())
        let failed = expectation(description: "异步编码错误")
        pipeline.pipeline.errorHandler = { error in XCTAssertTrue(error is Failure); failed.fulfill() }
        pipeline.start(); pipeline.recorderSink.runtimeErrorHandler?(Failure.injected); pipeline.recorderSink.runtimeErrorHandler?(Failure.injected)
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(pipeline.state, .failed); XCTAssertEqual(source.cancels, 1)
    }
}

private final class ManualCameraSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    var starts = 0; var cancels = 0
    func start() { starts += 1 }
    func pause() {}
    func resume() {}
    func stop() { delegate?.mediaSourceDidFinish(self) }
    func cancel() { cancels += 1 }
}
#endif
