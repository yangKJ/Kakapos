//
//  AudioCopyContractTests.swift
//  KakaposIntegrationTests
//
//  Created by Condy on 2026/11/16.
//

#if os(macOS)
import AVFoundation
import XCTest
@testable import KakaposMediaCore
@testable import KakaposVideo

final class AudioCopyContractTests: XCTestCase {
    func testNewExportPoliciesPreserveLegacyDefaults() {
        XCTAssertEqual(VideoExportProfile().audioPolicy, .encoded)
        XCTAssertNil(VideoExportProfile().allowsVideoFrameReordering)
    }

    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4") }

    private func fixture(rate: Double, channels: Int) throws -> URL {
        let output = url()
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 64
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 128_000
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        writer.add(video)
        writer.add(audio)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var storage: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 96, 64, kCVPixelFormatType_32BGRA, nil, &storage), kCVReturnSuccess)
        let frame = try XCTUnwrap(storage)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 128, CVPixelBufferGetBytesPerRow(frame) * 64)
        CVPixelBufferUnlockBaseAddress(frame, [])
        for i in 0..<18 {
            try waitReady(video, writer: writer)
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(i), timescale: 30)))
        }
        video.markAsFinished()
        var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description), noErr)
        let format = try XCTUnwrap(description)
        let total = Int(rate * 0.6)
        for start in stride(from: 0, to: total, by: 1024) {
            let count = min(1024, total - start)
            var samples = [Float]()
            for i in 0..<count {
                for channel in 0..<channels {
                    let phase = 2 * Double.pi * Double(440 + channel * 110) * Double(start + i) / rate
                    samples.append(Float(0.2 * sin(phase)))
                }
            }
            let bytes = samples.count * 4
            var block: CMBlockBuffer?
            XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block), noErr)
            let data = try XCTUnwrap(block)
            XCTAssertEqual(samples.withUnsafeMutableBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data, offsetIntoDestination: 0, dataLength: bytes)
            }, noErr)
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(rate)),
                presentationTimeStamp: CMTime(value: Int64(start), timescale: Int32(rate)), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
                formatDescription: format, sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
            try waitReady(audio, writer: writer)
            XCTAssertTrue(audio.append(try XCTUnwrap(sample)))
        }
        audio.markAsFinished()
        let done = expectation(description: "生成带音轨素材")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, String(describing: writer.error))
        return output
    }

    private func waitReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) throws {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        guard input.isReadyForMoreMediaData else { throw writer.error ?? NSError(domain: "素材生成超时", code: 1) }
    }

    private func packets(_ asset: AVAsset) throws -> [Data] {
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .audio).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var values: [Data] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                XCTAssertNil(CMSampleBufferGetImageBuffer(sample))
                continue
            }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let count = bytes.count
            XCTAssertEqual(bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!)
            }, noErr)
            values.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        return values
    }

    func testProcessedVideoPreserves44100MonoAnd48000StereoAudioPackets() throws {
        for (rate, channels) in [(44_100.0, 1), (48_000.0, 2)] {
            let sourceURL = try fixture(rate: rate, channels: channels)
            let output = url()
            defer {
                try? FileManager.default.removeItem(at: sourceURL)
                try? FileManager.default.removeItem(at: output)
            }
            let source = AVURLAsset(url: sourceURL)
            var copied = false
            let job = ReaderWriterExportJob(asset: source, outputURL: output, videoProcessors: [PassthroughFrameProcessor()],
                exportProfile: .init(videoCodec: .h264, colorPolicy: .standardDisplayP3, audioPolicy: .preserveCompatible),
                sessionFactory: { asset, url, configuration in
                    XCTAssertEqual(configuration.videoEncodingStrategy, .encoded)
                    let session = try VideoAssetExportSession(asset: asset, outputURL: url, configuration: configuration)
                    copied = session.copiesAudioSamples
                    return session
                })
            let done = expectation(description: "画面处理与声音直通")
            job.export { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
                done.fulfill()
            }
            wait(for: [done], timeout: 20)
            XCTAssertTrue(copied)
            XCTAssertEqual(job.status, .completed)
            XCTAssertGreaterThan(job.performanceSnapshot.processorInvocationCount, 0)
            let result = AVURLAsset(url: output)
            XCTAssertEqual(try packets(result), try packets(source))
            let track = try XCTUnwrap(result.tracks(withMediaType: .audio).first)
            let format = try XCTUnwrap(track.formatDescriptions.first) as! CMAudioFormatDescription
            let description = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
            XCTAssertEqual(description.mSampleRate, rate)
            XCTAssertEqual(description.mChannelsPerFrame, UInt32(channels))
            let original = try XCTUnwrap(source.tracks(withMediaType: .audio).first)
            XCTAssertEqual(track.timeRange.start.seconds, original.timeRange.start.seconds, accuracy: 0.002)
            XCTAssertEqual(track.timeRange.duration.seconds, original.timeRange.duration.seconds, accuracy: 0.002)
            XCTAssertEqual(result.duration.seconds, source.duration.seconds, accuracy: 0.03)
        }
    }

    func testAudioCopyConstructionFailureRemovesPartialFileAndRetriesEncoding() throws {
        let sourceURL = try fixture(rate: 48_000, channels: 2)
        let output = url()
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: output)
        }
        var attempts = 0
        let job = ReaderWriterExportJob(asset: AVURLAsset(url: sourceURL), outputURL: output,
            videoProcessors: [PassthroughFrameProcessor()],
            exportProfile: .init(videoCodec: .h264, audioPolicy: .preserveCompatible),
            sessionFactory: { asset, url, configuration in
                attempts += 1
                if attempts == 1 {
                    XCTAssertTrue(configuration.preservesCompatibleAudio)
                    try Data([0]).write(to: url)
                    throw NSError(domain: "模拟声音直通不兼容", code: 1)
                }
                XCTAssertFalse(configuration.preservesCompatibleAudio)
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                let session = try VideoAssetExportSession(asset: asset, outputURL: url, configuration: configuration)
                XCTAssertFalse(session.copiesAudioSamples)
                return session
            })
        let done = expectation(description: "清理局部产物后重编码")
        job.export { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(job.status, .completed)
    }

    func testAudioCopyRejectsMixTrimAndDefaultPolicy() throws {
        let sourceURL = try fixture(rate: 48_000, channels: 2)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        for scenario in 0..<3 {
            let output = url()
            defer { try? FileManager.default.removeItem(at: output) }
            let source = AVURLAsset(url: sourceURL)
            let job = ReaderWriterExportJob(asset: source, outputURL: output,
                timeRange: scenario == 1 ? CMTimeRange(start: .zero, duration: CMTime(seconds: 0.3, preferredTimescale: 600)) : nil,
                audioMix: scenario == 0 ? AVMutableAudioMix() : nil, videoProcessors: [PassthroughFrameProcessor()],
                exportProfile: .init(videoCodec: .h264, audioPolicy: scenario == 2 ? .encoded : .preserveCompatible),
                sessionFactory: { asset, url, configuration in
                    let session = try VideoAssetExportSession(asset: asset, outputURL: url, configuration: configuration)
                    XCTAssertFalse(session.copiesAudioSamples)
                    return session
                })
            let done = expectation(description: "声音重编码回退")
            job.export { result in
                if case .failure(let error) = result { XCTFail(String(describing: error)) }
                done.fulfill()
            }
            wait(for: [done], timeout: 20)
            XCTAssertEqual(job.status, .completed)
        }
    }
}
#endif
