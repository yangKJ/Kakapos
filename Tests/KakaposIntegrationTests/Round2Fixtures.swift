// 作者：Condy
#if os(macOS)
import AVFoundation
import AudioToolbox
import XCTest
import KakaposMediaCore
import KakaposVideo

enum Round2Fixtures {
    static func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4") }
    static func time(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }
    static func range(_ start: Double, _ duration: Double) -> CMTimeRange { CMTimeRange(start: time(start), duration: time(duration)) }
    static func asset() -> AVAsset {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return AVURLAsset(url: root.appendingPathComponent("KakaposExamples/IMG_3156.MOV"))
    }
    static func frame(_ index: Int, time: Double? = nil) throws -> PixelBufferFrame {
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &value), kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 { for x in 0..<64 {
            let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
            base[offset] = index % 3 == 2 ? 255 : 0; base[offset + 1] = index % 3 == 1 ? 255 : 0
            base[offset + 2] = index % 3 == 0 ? 255 : 0; base[offset + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return PixelBufferFrame(pixelBuffer: buffer, metadata: .init(presentationTime: time.map(Self.time) ?? CMTime(value: Int64(index), timescale: 30),
            duration: CMTime(value: 1, timescale: 30), frameIndex: Int64(index)))
    }
    static func audioFrame(_ index: Int) throws -> SampleBufferFrame {
        var description = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 32, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: 32, flags: 0, blockBufferOut: &block), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = 2
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format,
            sampleCount: 16, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample), noErr)
        return SampleBufferFrame(sampleBuffer: try XCTUnwrap(sample), metadata: .init(presentationTime: .zero, frameIndex: Int64(index)))
    }
    static func colors(_ url: URL) throws -> [Int] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var values: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let p = 32 * CVPixelBufferGetBytesPerRow(buffer) + 32 * 4
            let channels = [Int(bytes[p + 2]), Int(bytes[p + 1]), Int(bytes[p])]
            values.append(channels.enumerated().max(by: { $0.element < $1.element })!.offset)
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        XCTAssertEqual(reader.status, .completed)
        return values
    }
    static func movie(_ test: XCTestCase, framesPerSecond: Int = 30, colorIndex: Int = 0) throws -> URL {
        let output = url()
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64, AVVideoColorPropertiesKey: VideoExportColorPolicy.standardBT709.colorProperties!])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let frame = try self.frame(colorIndex)
        for i in 0..<(framesPerSecond * 2) {
            let end = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < end { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertTrue(adaptor.append(frame.pixelBuffer, withPresentationTime: CMTime(value: Int64(i), timescale: Int32(framesPerSecond))))
        }
        input.markAsFinished()
        let done = test.expectation(description: "离线源生成")
        writer.finishWriting { done.fulfill() }; test.wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
        return output
    }
}
#endif
