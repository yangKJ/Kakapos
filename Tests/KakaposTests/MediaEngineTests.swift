import XCTest
import AVFoundation
import CoreGraphics
@testable import Kakapos

final class MediaEngineTests: XCTestCase {

    func testPassthroughFrameProcessorPreservesPixelBufferMetadata() throws {
        let pixelBuffer = try makePixelBuffer(width: 16, height: 16)
        let metadata = FrameMetadata(
            presentationTime: CMTime(value: 12, timescale: 30),
            duration: CMTime(value: 1, timescale: 30),
            sourceTime: CMTime(value: 10, timescale: 30),
            trackTransform: .identity,
            frameIndex: 7
        )
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata)
        let expectation = self.expectation(description: "processor returns frame")

        PassthroughFrameProcessor().process(frame) { result in
            switch result {
            case .success(let output):
                XCTAssertEqual(output.metadata.presentationTime, metadata.presentationTime)
                XCTAssertEqual(output.metadata.duration, metadata.duration)
                XCTAssertEqual(output.metadata.sourceTime, metadata.sourceTime)
                XCTAssertEqual(output.metadata.frameIndex, metadata.frameIndex)
                XCTAssertEqual(CVPixelBufferGetWidth(output.pixelBuffer!), 16)
            case .failure(let error):
                XCTFail("Unexpected processor failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testMediaPipelineProcessesSourceFramesIntoSink() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let source = TestSource(frames: [input])
        let sink = TestSink()
        let processor = ClosureFrameProcessor { frame, completion in
            var output = frame
            output.metadata.frameIndex = 2
            completion(.success(output))
        }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])

        pipeline.start()

        XCTAssertEqual(sink.frames.count, 1)
        XCTAssertEqual(sink.frames.first?.metadata.frameIndex, 2)
    }

    func testTimelineCompositionCompilesEmptyComposition() {
        let timeline = TimelineComposition(renderSize: CGSize(width: 1920, height: 1080), frameDuration: CMTime(value: 1, timescale: 30))

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.videoComposition.renderSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(compiled.videoComposition.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(compiled.composition.tracks.count, 0)
        XCTAssertEqual(compiled.audioMix.inputParameters.count, 0)
        XCTAssertEqual(compiled.renderInstructions.count, 0)
    }

    func testTimelineCompositionFlattensGroupLayerIntoResolvedLayers() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let child = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let group = GroupLayer(
            timeRange: CMTimeRange(start: CMTime(value: 60, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            layers: [child],
            layerLevel: 3
        )
        let timeline = TimelineComposition(layers: [group])

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.resolvedLayers.videoLayers.count, 1)
        XCTAssertEqual(compiled.resolvedLayers.videoLayers.first?.timeRange.start, CMTime(value: 60, timescale: 30))
        XCTAssertEqual(compiled.resolvedLayers.videoLayers.first?.layerLevel, 3)
    }

    func testTimelineCompositionReusesSingleVideoTrackForNonOverlappingClips() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let first = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let second = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: CMTime(value: 30, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: CMTime(value: 30, timescale: 30), duration: CMTime(value: 30, timescale: 30))
        )
        let timeline = TimelineComposition(layers: [first, second])

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.composition.tracks(withMediaType: .video).count, 1)
        XCTAssertEqual(compiled.renderInstructions.count, 2)
        XCTAssertEqual(compiled.renderInstructions.map(\.sourceTrackIDs.count), [1, 1])
    }

    func testKeyframeAnimationAppliesEaseInOutInterpolation() throws {
        let animation = KeyframeAnimation(
            keyPath: "opacity",
            values: [0, 1],
            keyTimes: [.zero, CMTime(value: 10, timescale: 10)],
            easing: .easeInOut
        )

        let quarterPoint = try XCTUnwrap(animation.value(at: CMTime(value: 25, timescale: 100)))
        let lookupValue = try XCTUnwrap(
            KeyframeAnimation.value(for: "opacity", at: CMTime(value: 25, timescale: 100), animations: [animation])
        )

        XCTAssertEqual(quarterPoint, 0.125, accuracy: 0.0001)
        XCTAssertEqual(lookupValue, 0.125, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoUsesVideoProgressWhenAudioTrackIsMissing() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.65,
            audioProgress: 0.1,
            hasVideo: true,
            hasAudio: false
        )

        XCTAssertEqual(info.fractionCompleted, 0.65, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoAveragesEnabledTracksAndClampsValues() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 1.2,
            audioProgress: -0.2,
            hasVideo: true,
            hasAudio: true
        )

        XCTAssertEqual(info.videoProgress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(info.audioProgress, 0.0, accuracy: 0.0001)
        XCTAssertEqual(info.fractionCompleted, 0.5, accuracy: 0.0001)
    }

    func testReaderWriterExportJobKeepsStableStatusOutsideExportingState() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let expectation = expectation(description: "cancel status callback")
        var receivedStatuses: [ReaderWriterExportJob.Status] = []
        job.statusHandler = { status in
            receivedStatuses.append(status)
            if status == .cancelled {
                expectation.fulfill()
            }
        }

        job.pause()
        XCTAssertEqual(job.status, .idle)

        job.resume()
        XCTAssertEqual(job.status, .idle)

        job.cancel()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(receivedStatuses, [.cancelled])

        job.resume()
        XCTAssertEqual(job.status, .cancelled)
    }

    func testVideoXExportPipelineDefaultsToAssetExportSession() {
        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: [:]), .assetExportSession)
    }

    func testVideoXExportPipelineCanSwitchToReaderWriter() {
        let options: [VideoX.Option: Any] = [
            .ExportPipeline: VideoX.ExportPipeline.readerWriter
        ]

        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: options), .readerWriter)
    }

    func testVideoXMakeExportJobReturnsNilForAssetExportSessionPipeline() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportJob = try exporter.makeExportJob(
            options: [:],
            instructions: [instruction]
        )

        XCTAssertNil(exportJob)
    }

    func testVideoXMakeExportJobReturnsReaderWriterJobWhenConfigured() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())
        let outputURL = try XCTUnwrap(exporter.provider.outputURL as URL?)

        let exportJob = try exporter.makeExportJob(
            options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
            instructions: [instruction]
        )

        XCTAssertNotNil(exportJob)
        XCTAssertEqual(exportJob?.status, .idle)
        XCTAssertEqual(try exporter.makeReaderWriterExportJob(instructions: [instruction]).status, .idle)
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "mp4")
    }

    func testVideoXMakeExportTaskReturnsAssetSessionTaskByDefault() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportTask = try exporter.makeExportTask(
            options: [:],
            instructions: [instruction]
        )

        XCTAssertNotNil(exportTask.assetExportSession)
        XCTAssertNil(exportTask.readerWriterJob)
        XCTAssertFalse(exportTask.supportsPauseResume)
        XCTAssertEqual(exportTask.status, .idle)
    }

    func testVideoXMakeExportTaskReturnsReaderWriterTaskWhenConfigured() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportTask = try exporter.makeExportTask(
            options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
            instructions: [instruction]
        )

        XCTAssertNil(exportTask.assetExportSession)
        XCTAssertNotNil(exportTask.readerWriterJob)
        XCTAssertTrue(exportTask.supportsPauseResume)
        XCTAssertEqual(exportTask.status, .idle)

        exportTask.pause()
        XCTAssertEqual(exportTask.status, .idle)
        exportTask.cancel()
        XCTAssertEqual(exportTask.status, .cancelled)
    }

    func testPreviewSinkBuildsPreviewImageAndPreservesMetadata() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let metadata = FrameMetadata(
            presentationTime: CMTime(value: 5, timescale: 30),
            sourceTime: CMTime(value: 4, timescale: 30),
            frameIndex: 9
        )
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata)
        let expectation = self.expectation(description: "preview sink callback")
        var receivedImage: CGImage?
        var receivedMetadata: FrameMetadata?

        let sink = PreviewSink { image, previewMetadata in
            receivedImage = image
            receivedMetadata = previewMetadata
            expectation.fulfill()
        }

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedImage?.width, 12)
        XCTAssertEqual(receivedImage?.height, 10)
        XCTAssertEqual(receivedMetadata?.frameIndex, metadata.frameIndex)
        XCTAssertEqual(receivedMetadata?.presentationTime, metadata.presentationTime)
    }

    func testMediaPipelineStopFinishesSinksOnlyOnceWhenSourceAlsoFinishes() {
        let source = StopAwareSource()
        let sink = CountingSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])
        let expectation = self.expectation(description: "completion called once")
        expectation.expectedFulfillmentCount = 1

        pipeline.completionHandler = {
            expectation.fulfill()
        }

        pipeline.stop()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(sink.finishCount, 1)
    }

    func testRecorderSinkFinishRecordingReturnsRecordedClip() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero)
        )
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30))
        )
        let appendExpectation = self.expectation(description: "append frames")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = self.expectation(description: "finish recording")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .finished)
        XCTAssertEqual(recordedClip?.outputURL, outputURL)
        XCTAssertEqual(recordedClip?.startedAt, .zero)
        XCTAssertEqual(recordedClip?.endedAt, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 1, timescale: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testRecorderSinkPauseResumeRemovesPausedGapFromClipDuration() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 90, timescale: 30)))
        let appendExpectation = expectation(description: "append frames around pause")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = expectation(description: "finish paused recording")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        sink.pauseRecording(at: CMTime(value: 30, timescale: 30))
        XCTAssertEqual(sink.state, .paused)
        sink.resumeRecording()
        XCTAssertEqual(sink.state, .recording)

        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 30, timescale: 30))
    }

    func testRecorderSinkFinishWhilePausedKeepsRecordedDuration() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 30, timescale: 30))
        )
        let appendExpectation = expectation(description: "append paused clip frames")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = expectation(description: "finish paused clip")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.pauseRecording(at: CMTime(value: 60, timescale: 30))
        XCTAssertEqual(sink.state, .paused)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .finished)
        XCTAssertEqual(recordedClip?.startedAt, .zero)
        XCTAssertEqual(recordedClip?.endedAt, CMTime(value: 30, timescale: 30))
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 30, timescale: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testCameraSessionLifecycleTracksStartInterruptionResumeAndStop() {
        var lifecycle = CameraSessionLifecycle(position: .back)

        XCTAssertEqual(lifecycle.handle(.startRequested), .willStart)
        XCTAssertEqual(lifecycle.state, .starting)
        XCTAssertEqual(lifecycle.handle(.didStartRunning), .didStart)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.handle(.wasInterrupted), .wasInterrupted)
        XCTAssertEqual(lifecycle.state, .interrupted)
        XCTAssertEqual(lifecycle.handle(.interruptionEnded), .interruptionEnded)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.handle(.didStopRunning), .didStop)
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testCameraSessionLifecycleTracksCameraPositionChanges() {
        var lifecycle = CameraSessionLifecycle(position: .back)

        XCTAssertEqual(lifecycle.handle(.positionChanged(.front)), .positionChanged(.front))
        XCTAssertEqual(lifecycle.position, .front)
    }

    func testCameraSessionLifecycleTracksRecoverableRuntimeErrors() {
        var lifecycle = CameraSessionLifecycle(position: .back)
        _ = lifecycle.handle(.startRequested)
        _ = lifecycle.handle(.didStartRunning)

        XCTAssertEqual(
            lifecycle.handle(.runtimeError(isRecoverable: true, description: "reset")),
            .runtimeError(isRecoverable: true, description: "reset")
        )
        XCTAssertEqual(lifecycle.state, .error)
        XCTAssertTrue(lifecycle.shouldAttemptRecovery)
    }
}

private final class TestSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private let frames: [MediaFrame]

    init(frames: [MediaFrame]) {
        self.frames = frames
    }

    func start() {
        frames.forEach { delegate?.mediaSource(self, didOutput: $0) }
        delegate?.mediaSourceDidFinish(self)
    }

    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}

private final class TestSink: MediaSink {
    var frames: [MediaFrame] = []

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        frames.append(frame)
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

private final class StopAwareSource: MediaSource {
    weak var delegate: MediaSourceDelegate?

    func start() {}
    func pause() {}
    func resume() {}

    func stop() {
        delegate?.mediaSourceDidFinish(self)
    }

    func cancel() {}
}

private final class CountingSink: MediaSink {
    var finishCount = 0

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        finishCount += 1
        completion(.success(()))
    }
}

private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    XCTAssertEqual(status, kCVReturnSuccess)
    return pixelBuffer!
}

private func makeSampleExporter() throws -> VideoX {
    let sampleURL = try makeSampleAssetURL()
    XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")
    return VideoX(provider: .init(with: sampleURL, to: outputURL))
}

private func makeSampleAssetURL() throws -> URL {
    let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("KakaposExamples")
        .appendingPathComponent("IMG_1388.mp4")
    XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    return sampleURL
}
