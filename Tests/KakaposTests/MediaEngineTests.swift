import XCTest
import AVFoundation
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

    func testVideoXExportPipelineDefaultsToAssetExportSession() {
        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: [:]), .assetExportSession)
    }

    func testVideoXExportPipelineCanSwitchToReaderWriter() {
        let options: [VideoX.Option: Any] = [
            .ExportPipeline: VideoX.ExportPipeline.readerWriter
        ]

        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: options), .readerWriter)
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
