// 作者：Condy
#if DEBUG && canImport(UIKit) && !os(watchOS)
import XCTest
import AVFoundation
import AudioToolbox
import KakaposMediaCore
@testable import KakaposCamera

final class CameraPlatformContractTests: XCTestCase {
    func testSyntheticPhotoLifecycleAudioOwnershipAndRecordingReplacement() async throws {
        try await CameraAcceptance.run()
    }
}

private enum CameraAcceptance {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "相机验收", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func wait(_ context: String = "", _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(20)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        try require(condition(), "等待条件超时：" + context)
    }
    static func frame(_ time: Double, audio: Bool = false) throws -> CMSampleBuffer {
        let timestamp = CMTime(seconds: time, preferredTimescale: 44_100)
        var sample: CMSampleBuffer?
        if audio {
            var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?; var block: CMBlockBuffer?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 2048, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: 2048, flags: 0, blockBufferOut: &block)
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 2048)
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid); var size = 2
            CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1024,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        } else {
            var buffer: CVPixelBuffer?; CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, []); memset(CVPixelBufferGetBaseAddress(buffer!), 128, CVPixelBufferGetBytesPerRow(buffer!) * 64); CVPixelBufferUnlockBaseAddress(buffer!, [])
            var format: CMVideoFormatDescription?; CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer!, formatDescriptionOut: &format)
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        }
        guard let sample else { throw NSError(domain: "夹具", code: 1) }; return sample
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try CameraSource(configuration: .init(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false))
        let delegate = PhotoObserver(); source.delegate = delegate
        source._detachNativeNotificationsForTesting(); source._setStateForTesting(.running)
        let old = try frame(0); source._emitForTesting(sampleBuffer: old, mediaType: .video)
        source._setStateForTesting(.running) // 重复开始不能清掉当前运行的有效帧。
        let accepted = ProbeValue(0); let replacement = ProbeValue(0)
        source.photoCaptureHandler = { _ in accepted.update { $0 += 1 } }
        source.capturePhotoFromCurrentFrame()
        source.photoCaptureHandler = { _ in replacement.update { $0 += 1 } }
        source.stop(); source._drainSessionQueueForTesting()
        try await wait("首张照片回调") { accepted.value == 1 }
        source._emitForTesting(sampleBuffer: old, mediaType: .video)
        source.capturePhotoFromCurrentFrame()
        try await wait("停机照片失败通知") { delegate.failures == 1 }
        try require(replacement.value == 0 && source.snapshot.lastFrameIndex == 1, "停机后缓存或回调泄漏")
        try await wait("终态交接") { !source._terminalHandoffForTesting.isPending }
        source._setStateForTesting(.running); source._setFrameTimeFenceForTesting(CMTime(value: 2, timescale: 1))
        source._emitForTesting(sampleBuffer: old, mediaType: .video)
        try require(source.snapshot.lastFrameIndex == 1, "旧运行帧进入新运行")
        source._emitForTesting(sampleBuffer: try frame(2), mediaType: .video)
        source.capturePhotoFromCurrentFrame(); try await wait("重启照片") { replacement.value == 1 }
        source.stop(); source._drainSessionQueueForTesting()

        enum Failure: Error { case injected }
        let session = AVCaptureSession()
        let a = try CameraSource(session: session, configuration: .init(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false))
        let b = try CameraSource(session: session, configuration: .init(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false))
        try require(a.sessionOwner === b.sessionOwner, "共享会话出现多个 owner")
        let before = session.outputs.count
        do {
            try a._configureTransactionForTesting { graph in
                let output = AVCaptureVideoDataOutput()
                try require(graph.canAddOutput(output), "空会话无法加入测试输出")
                graph.addOutput(output); throw Failure.injected
            }
        } catch Failure.injected {}
        try require(session.outputs.count == before, "失败配置未撤回输出")

        let activations = ProbeValue(0); let releases = ProbeValue(0)
        let leases = CameraAudioLeaseCoordinator(activate: { _ in activations.update { $0 += 1 } }, deactivate: { releases.update { $0 += 1 } })
        var audioSources: [CameraSource] = []
        for mode in [CameraCaptureMode.photo, .videoWithoutAudio, .video, .video] {
            let item = try CameraSource(configuration: .init(captureMode: mode, automaticallyRequestsAuthorization: false))
            item._useAudioSessionControllerForTesting(CameraAudioSessionController(coordinator: leases))
            item._detachNativeNotificationsForTesting(); item._setStateForTesting(.running); try item._acquireRunAudioForTesting(); audioSources.append(item)
        }
        try require(activations.value == 1 && !audioSources[0].audioSessionController.isActive && !audioSources[1].audioSessionController.isActive, "无音频场景取得租约")
        audioSources[2].stop(); audioSources[2]._drainSessionQueueForTesting(); try require(releases.value == 0, "首个分支提前停用全局音频")
        audioSources[3].stop(); audioSources[3]._drainSessionQueueForTesting(); try require(releases.value == 1, "最后分支未释放音频")
        for item in audioSources { item.stop() }

        let engine = try CameraEngine(configuration: .init(captureMode: .video, automaticallyRequestsAuthorization: false,
            video: .init(dimensions: CGSize(width: 64, height: 64))))
        engine.source._detachNativeNotificationsForTesting(); engine.source._setStateForTesting(.running)
        let first = try engine.makeRecordingController(outputURL: root.appendingPathComponent("first.mp4")); first.start()
        engine.source._emitForTesting(sampleBuffer: try frame(0), mediaType: .video)
        engine.source._emitForTesting(sampleBuffer: try frame(0.01, audio: true), mediaType: .audio)
        do { try await wait("首个录制音频") { first.recorderSink.recordingCadence.audioSampleBufferCount == 1 } }
        catch { throw NSError(domain: "相机验收", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription)；\(first.summaryText)；\(String(describing: first.recorderSink.failureError))"]) }
        let gate = DispatchSemaphore(value: 0); let signal = ProbeSignal()
        first.recorderSink._willFinishWritingForTesting = { signal.mark(); _ = gate.wait(timeout: .now() + 8) }
        let firstDone = ProbeSignal()
        engine.stopRecording { _ in firstDone.mark() }
        try await wait("旧录制进入收尾") { signal.value }
        let publishing = ProbeSignal(); let publishGate = DispatchSemaphore(value: 0)
        let secondValue = ProbeValue<CameraRecordingController?>(nil)
        let creationError = ProbeValue<String?>(nil)
        engine._beforePublishingRecordingForTesting = { publishing.mark(); _ = publishGate.wait(timeout: .now() + 8) }
        let engineBox = ProbeValue(engine)
        defer { gate.signal(); publishGate.signal() }
        DispatchQueue.global().async {
            let engine = engineBox.value
            do {
                let controller = try engine.makeRecordingController(outputURL: root.appendingPathComponent("second.mp4"))
                controller.start(); secondValue.update { $0 = controller }
            } catch { creationError.update { $0 = String(describing: error) } }
        }
        try await wait("新控制器发布前") { publishing.value }
        gate.signal(); try await wait("旧录制完成返回") { firstDone.value }
        try require(engine.source.state == .running, "旧完成在新控制器发布前停止了共享源")
        publishGate.signal(); try await wait("新控制器构造返回") { secondValue.value != nil || creationError.value != nil }
        if let error = creationError.value { throw NSError(domain: error, code: 1) }
        let second = secondValue.value!
        engine._beforePublishingRecordingForTesting = nil
        engine.source._emitForTesting(sampleBuffer: try frame(1), mediaType: .video)
        engine.source._emitForTesting(sampleBuffer: try frame(1.01, audio: true), mediaType: .audio)
        try await wait("新录制音频") { second.recorderSink.recordingCadence.audioSampleBufferCount == 1 }
        try require(engine.source.state == .running && second.state == .recording, "旧结束回调停止了新录制")
        let secondDone = ProbeSignal(); let secondClip = ProbeValue<RecordedClip?>(nil)
        engine.stopRecording { response in secondClip.update { $0 = try? response.get() }; secondDone.mark() }
        try await wait("新录制收尾") { secondDone.value }
        try require(secondClip.value?.containsAudio == true && secondClip.value?.containsVideo == true, "标准录制入口遗漏音频配置")
        engine.cancel()
    }
}
private final class PhotoObserver: MediaSourceDelegate {
    private let stored = ProbeValue(0)
    var failures: Int { stored.value }
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}
    func mediaSource(_ source: MediaSource, didFail error: Error) { stored.update { $0 += 1 } }
    func mediaSourceDidFinish(_ source: MediaSource) {}
}
private final class ProbeSignal: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func mark() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private final class ProbeValue<Value>: @unchecked Sendable {
    private let lock = NSLock(); private var stored: Value
    init(_ value: Value) { stored = value }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
}

#endif
