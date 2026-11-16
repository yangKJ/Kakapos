// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
import KakaposMediaCore
import KakaposVideo
import KakaposTimeline

final class TimelineArtifactAcceptanceTests: XCTestCase {
    func testInteriorOpacityPeakSurvivesRealTimelineExport() throws {
        let source = try makeRedSource()
        let output = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 2, timescale: 1))
        let clip = ClipLayer(asset: AVURLAsset(url: source), timeRange: range, sourceTimeRange: range)
        clip.keyframes = [.init(keyPath: "opacity", values: [0, 1, 0],
            keyTimes: [.zero, CMTime(value: 1, timescale: 1), CMTime(value: 2, timescale: 1)])]
        let compiled = TimelineComposition(renderSize: CGSize(width: 64, height: 64), layers: [clip]).compile()
        XCTAssertTrue(compiled.isValid)
        let done = expectation(description: "真实时间线产物导出")
        let job = compiled.makeExportJob(outputURL: output)
        job.export { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(job.status, .completed)
        let values = try redSamples(from: output)
        func red(at time: Double) throws -> Int {
            try XCTUnwrap(values.min { abs($0.0 - time) < abs($1.0 - time) }).1
        }
        let peak = try red(at: 1)
        XCTAssertGreaterThan(peak, 200)
        XCTAssertGreaterThan(peak - (try red(at: 0.1)), 100)
        XCTAssertGreaterThan(peak - (try red(at: 1.9)), 100)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    }

    private func makeRedSource() throws -> URL {
        let url = temporaryURL()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
            AVVideoColorPropertiesKey: VideoExportColorPolicy.standardBT709.colorProperties!
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &value), kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                base[offset] = 0; base[offset + 1] = 0; base[offset + 2] = 255; base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for index in 0..<60 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        let done = expectation(description: "红色测试源生成")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func redSamples(from url: URL) throws -> [(Double, Int)] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var result: [(Double, Int)] = []
        while let sample = output.copyNextSampleBuffer() {
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            result.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                Int(base[32 * CVPixelBufferGetBytesPerRow(buffer) + 32 * 4 + 2])))
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertGreaterThan(result.count, 50)
        return result
    }
}
#endif
