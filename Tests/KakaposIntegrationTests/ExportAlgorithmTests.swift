// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
@testable import KakaposMediaCore
@testable import KakaposVideo

final class ExportAlgorithmTests: XCTestCase {
    private func asset() -> AVAsset {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return AVURLAsset(url: root.appendingPathComponent("KakaposExamples/IMG_3156.MOV"))
    }
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4") }
    private func packets(_ asset: AVAsset, mediaType: AVMediaType = .video) throws -> [Data] {
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: mediaType).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var result: [Data] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                XCTAssertNil(CMSampleBufferGetImageBuffer(sample), "压缩读取不可交付解码像素")
                continue
            }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            XCTAssertEqual(status, noErr)
            result.append(data)
        }
        XCTAssertEqual(reader.status, .completed)
        return result
    }
    private func makeSDRFixture() throws -> URL {
        let output = url()
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 0, CVPixelBufferGetBytesPerRow(frame) * 64)
        CVPixelBufferUnlockBaseAddress(frame, [])
        for i in 0..<12 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(i), timescale: 30)))
        }
        input.markAsFinished()
        let done = expectation(description: "SDR 输入生成")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
        return output
    }
    func testCompatibleSampleCopyPreservesEveryCompressedVideoPacket() throws {
        let source = asset()
        let output = url()
        defer { try? FileManager.default.removeItem(at: output) }
        let track = try XCTUnwrap(source.tracks(withMediaType: .video).first)
        let description = try XCTUnwrap(track.formatDescriptions.first) as! CMFormatDescription
        let codec: VideoExportCodec = CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_HEVC ? .hevc : .h264
        let audioTrack = source.tracks(withMediaType: .audio).first
        let audioFormat = audioTrack?.formatDescriptions.first.map { $0 as! CMAudioFormatDescription }
        let audio = audioFormat.flatMap(CMAudioFormatDescriptionGetStreamBasicDescription)?.pointee
        let audioRate = max(32_000, Int(audioTrack?.estimatedDataRate ?? 128_000))
        let profile = VideoExportProfile(videoCodec: codec, audioBitRate: audioRate,
            audioSampleRate: audio?.mSampleRate ?? 44_100, audioChannelCount: Int(audio?.mChannelsPerFrame ?? 2), copiesSamplesWhenCompatible: true)
        let done = expectation(description: "无重编码导出")
        var strategy: VideoAssetExportSession.Configuration.VideoEncodingStrategy?
        let job = ReaderWriterExportJob(asset: source, outputURL: output, exportProfile: profile,
            shouldOptimizeForNetworkUse: true, metadata: [], sessionFactory: { asset, url, configuration in
                strategy = configuration.videoEncodingStrategy
                let session = try VideoAssetExportSession(asset: asset, outputURL: url, configuration: configuration)
                return session
            })
        job.export { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        guard case .compressedCopy? = strategy else { return XCTFail("兼容输入没有使用压缩样本复制") }
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(try packets(AVURLAsset(url: output)), try packets(source))
        if audio?.mFormatID == kAudioFormatMPEG4AAC, (audioTrack?.estimatedDataRate ?? 0) >= 32_000 {
            XCTAssertEqual(try packets(AVURLAsset(url: output), mediaType: .audio), try packets(source, mediaType: .audio))
        }
        XCTAssertEqual(AVURLAsset(url: output).duration.seconds, source.duration.seconds, accuracy: 0.05)
        XCTAssertEqual(job.performanceSnapshot.processorInvocationCount, 0)
    }
    func testCopyAdmissionRejectsProcessingTrimmingAndExplicitBitrate() {
        for scenario in 0..<5 {
            let source = asset()
            let stub = ExportAdmissionStub()
            var strategy: VideoAssetExportSession.Configuration.VideoEncodingStrategy?
            let profile = VideoExportProfile(videoCodec: .h264, averageVideoBitRate: scenario == 2 ? 1_000_000 : nil,
                copiesSamplesWhenCompatible: scenario != 3, allowsVideoFrameReordering: scenario == 4 ? false : nil)
            let job = ReaderWriterExportJob(asset: source, outputURL: url(),
                timeRange: scenario == 1 ? CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)) : nil,
                videoProcessors: scenario == 0 ? [PassthroughFrameProcessor()] : [], exportProfile: profile,
                shouldOptimizeForNetworkUse: true, metadata: [], sessionFactory: { _, _, configuration in
                    strategy = configuration.videoEncodingStrategy
                    return stub
                })
            job.export { _ in }
            if case .compressedCopy? = strategy { XCTFail("不兼容场景不可复制压缩样本：\(scenario)") }
            XCTAssertNotNil(strategy)
        }
    }
    func testSampleCopyConstructionFailureFallsBackToEncoding() {
        var attempts: [VideoAssetExportSession.Configuration.VideoEncodingStrategy] = []
        let source = asset()
        let profile = VideoExportProfile(videoCodec: .hevc, copiesSamplesWhenCompatible: true)
        let job = ReaderWriterExportJob(asset: source, outputURL: url(), exportProfile: profile,
            shouldOptimizeForNetworkUse: true, metadata: [], sessionFactory: { _, _, configuration in
                attempts.append(configuration.videoEncodingStrategy)
                if configuration.videoEncodingStrategy == .compressedCopy { throw NSError(domain: "测试", code: 1) }
                return ExportAdmissionStub()
            })
        job.export { _ in }
        XCTAssertEqual(attempts.count, 2)
        guard attempts.count == 2 else { return }
        if case .compressedCopy = attempts[0] {} else { XCTFail("首次应尝试样本复制") }
        if case .encoded = attempts[1] {} else { XCTFail("失败后应使用编码") }
        XCTAssertEqual(job.status, .completed)
    }
    func testNativeYUVExportKeepsProcessingSerialAndReadAheadBounded() throws {
        let processor = NativeYUVProbe()
        let sourceURL = try makeSDRFixture()
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let output = url()
        defer { try? FileManager.default.removeItem(at: output) }
        let done = expectation(description: "原生格式与有界预取导出")
        let job = ReaderWriterExportJob(asset: AVURLAsset(url: sourceURL), outputURL: output, videoProcessors: [processor], exportProfile: .init(videoReadAheadFrameCount: 2))
        job.export { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        XCTAssertEqual(job.status, .completed)
        XCTAssertGreaterThan(processor.formats.count, 0)
        XCTAssertTrue(processor.formats.allSatisfy { $0 == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange })
        let performance = job.performanceSnapshot
        XCTAssertGreaterThan(performance.peakPrefetchedVideoSampleCount, 0)
        XCTAssertLessThanOrEqual(performance.peakPrefetchedVideoSampleCount, 2)
        XCTAssertEqual(performance.peakProcessorInFlightCount, 1)
        XCTAssertEqual(performance.videoSamplesRead, performance.videoSamplesWritten)
        XCTAssertGreaterThan(performance.videoSamplesWritten, 0)
    }
    func testReadAheadExportCancelsAndRejectsLateProcessorOutput() {
        let started = expectation(description: "预取导出已进入处理器")
        let finished = expectation(description: "取消不等待外部处理器")
        let processor = DeferredReadAheadProcessor(started: started)
        let output = url()
        defer { try? FileManager.default.removeItem(at: output) }
        let job = ReaderWriterExportJob(asset: asset(), outputURL: output, videoProcessors: [processor],
            exportProfile: .init(videoReadAheadFrameCount: 2))
        job.export { result in
            guard case .failure = result else { XCTFail("取消后不可成功"); finished.fulfill(); return }
            finished.fulfill()
        }
        wait(for: [started], timeout: 5)
        job.cancel()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(processor.cancellations, 1)
        processor.deliverLate()
        let barrier = expectation(description: "处理迟到回调")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { barrier.fulfill() }
        wait(for: [barrier], timeout: 2)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testReaderCancellationRunsAfterTheCurrentReadReturns() throws {
        let source = asset()
        let reader = try OrderedCancellationReader(asset: source)
        let output = BlockingReadOutput(track: try XCTUnwrap(source.tracks(withMediaType: .video).first), outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let cancelled = expectation(description: "读帧退出后拆除 Reader")
        reader.willCancel = { cancelled.fulfill() }
        let prefetcher = VideoSamplePrefetcher(reader: reader, output: output, capacity: 2, pressure: { _ in }, available: {})
        prefetcher.start()
        XCTAssertEqual(output.started.wait(timeout: .now() + 2), .success)
        prefetcher.cancel()
        XCTAssertEqual(reader.status, .reading, "读帧尚未退出时不可拆除系统资源")
        output.allowReturn.signal()
        wait(for: [cancelled], timeout: 2)
    }
    func testReadAheadKeepsReaderAliveUntilCancelledReadReturns() throws {
        let released = expectation(description: "读取退出后释放 Reader")
        var reader: ReaderLifetimeProbe? = try ReaderLifetimeProbe(asset: asset())
        reader?.didDeinitialize = { released.fulfill() }
        weak var weakReader = reader
        let output = BlockingReadOutput(track: try XCTUnwrap(asset().tracks(withMediaType: .video).first), outputSettings: nil)
        var prefetcher: VideoSamplePrefetcher? = VideoSamplePrefetcher(reader: try XCTUnwrap(reader), output: output,
            capacity: 2, pressure: { _ in }, available: {})
        prefetcher?.start()
        XCTAssertEqual(output.started.wait(timeout: .now() + 2), .success)
        reader = nil
        prefetcher?.cancel()
        prefetcher = nil
        XCTAssertNotNil(weakReader, "正在执行读取时不可释放其会话 owner")
        output.allowReturn.signal()
        wait(for: [released], timeout: 2)
        XCTAssertNil(weakReader)
    }
    func testCompressedDecodeOrderProgressIsFiniteBoundedAndMonotonic() {
        let progress = VideoAssetExportSession.ExportProgress(tracksAudioEncoding: false, tracksVideoEncoding: true)
        progress.updateVideoEncodingProgress(fractionCompleted: .nan)
        XCTAssertEqual(progress.videoProgress?.fractionCompleted, 0)
        progress.updateVideoEncodingProgress(fractionCompleted: 0.7)
        progress.updateVideoEncodingProgress(fractionCompleted: 0.3)
        XCTAssertEqual(progress.videoProgress?.fractionCompleted, 0.7)
        progress.updateVideoEncodingProgress(fractionCompleted: 2)
        XCTAssertEqual(progress.videoProgress?.fractionCompleted, 1)
    }
    func testReadAheadProfilePreservesDefaultAndBoundsOptInCapacity() {
        XCTAssertEqual(VideoExportProfile().videoReadAheadFrameCount, 0)
        XCTAssertEqual(VideoExportProfile(videoReadAheadFrameCount: -1).videoReadAheadFrameCount, 0)
        XCTAssertEqual(VideoExportProfile(videoReadAheadFrameCount: 100).videoReadAheadFrameCount, 2)
    }
    func testPixelFormatNegotiationRequiresExplicitWholeChainAdmission() {
        let native = NativeYUVProbe()
        XCTAssertEqual(negotiatedVideoPixelFormat(processors: [native], fallback: kCVPixelFormatType_32BGRA, sourceCodec: kCMVideoCodecType_H264), kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        XCTAssertEqual(negotiatedVideoPixelFormat(processors: [native, PassthroughFrameProcessor()], fallback: kCVPixelFormatType_32BGRA, sourceCodec: kCMVideoCodecType_H264), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(negotiatedVideoPixelFormat(processors: [native], fallback: kCVPixelFormatType_32BGRA, sourceCodec: kCMVideoCodecType_HEVCWithAlpha), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(negotiatedVideoPixelFormat(processors: [native], fallback: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, sourceCodec: kCMVideoCodecType_HEVC), kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    }
}
private final class DeferredReadAheadProcessor: CancellableFrameProcessor, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (MediaFrame, (Result<MediaFrame, Error>) -> Void)?
    private var count = 0
    private let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    var cancellations: Int { lock.lock(); defer { lock.unlock() }; return count }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        _ = processCancellable(frame, completion: completion)
    }
    func processCancellable(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) -> FrameProcessingOperation {
        lock.lock(); pending = (frame, completion); lock.unlock()
        started.fulfill()
        return FrameProcessingCancellation { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.count += 1; self.lock.unlock()
        }
    }
    func deliverLate() {
        lock.lock(); let value = pending; pending = nil; lock.unlock()
        if let value { value.1(.success(value.0)) }
    }
}
private final class OrderedCancellationReader: AVAssetReader, @unchecked Sendable {
    var willCancel: (() -> Void)?
    override func cancelReading() { super.cancelReading(); willCancel?() }
}
private final class ReaderLifetimeProbe: AVAssetReader, @unchecked Sendable {
    var didDeinitialize: (() -> Void)?
    deinit { didDeinitialize?() }
}
private final class BlockingReadOutput: AVAssetReaderTrackOutput, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let allowReturn = DispatchSemaphore(value: 0)
    override func copyNextSampleBuffer() -> CMSampleBuffer? {
        started.signal()
        allowReturn.wait()
        return nil
    }
}
private final class ExportAdmissionStub: ReaderWriterExportSession {
    func export(progress: ((VideoAssetExportSession.ExportProgress) -> Void)?, status: ((VideoAssetExportSession.Status) -> Void)?, completion: @escaping (Error?) -> Void) { completion(nil) }
    func pause() {}
    func resume() {}
    func cancel() {}
}
private final class NativeYUVProbe: FrameProcessor, FrameProcessorCapabilityProviding, @unchecked Sendable {
    let capabilities = FrameProcessorCapabilities(acceptedPixelFormats: [.yuv420BiPlanarFullRange], supportedDynamicRanges: [.standard])
    private let lock = NSLock()
    private var observed: [OSType] = []
    var formats: [OSType] { lock.lock(); defer { lock.unlock() }; return observed }
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        if let buffer = extractPixelBuffer(frame) {
            lock.lock(); observed.append(CVPixelBufferGetPixelFormatType(buffer)); lock.unlock()
        }
        completion(.success(frame))
    }
}
#endif
