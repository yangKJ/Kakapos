// 作者：Condy
#if DEBUG && canImport(UIKit) && !os(watchOS)
import XCTest
import AVFoundation
import CoreImage
import KakaposMediaCore
@testable import KakaposCamera
#if canImport(ARKit)
import ARKit
#endif

final class CameraRecoveryPlatformTests: XCTestCase {
    func testPreviewLifecycleOwnership() async throws { try await CameraRecoveryAcceptance.previewLifecycle() }
    func testRecordingEntryConfigurationAndMaximumDuration() async throws { try await CameraRecoveryAcceptance.recordingLimits() }
    func testInitializationUsesSharedSessionOwner() async throws { try await CameraRecoveryAcceptance.initializationOwner() }
    func testQueuedPositionSwitchRespectsRunIdentity() async throws { try await CameraRecoveryAcceptance.positionSwitch() }
    func testARResumeUsesHostRunOperation() throws { try CameraRecoveryAcceptance.arResume() }
    func testEmptyAndDynamicObserverRoutes() async throws { try await CameraRecoveryAcceptance.observerRoutes() }
    func testLegacyPhotoWaitsForFinalResultAndKeepsAcceptedDelivery() async throws { try await CameraRecoveryAcceptance.legacyPhotoTerminal() }
    func testNativePhotoCancellationReleasesSlotAndLateFiles() async throws { try await CameraRecoveryAcceptance.nativeCancellation() }
    func testNativePhotoFilesAreIsolatedAcrossAttempts() throws { try CameraRecoveryAcceptance.nativeResources() }
    func testCancellationDuringPhotoFilePublication() async throws { try await CameraRecoveryAcceptance.nativeWriteRace() }
}

enum CameraRecoveryAcceptance {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "相机恢复验收", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func wait(_ name: String, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() && Date() < end { try await Task.sleep(nanoseconds: 5_000_000) }
        try require(condition(), "等待超时：" + name)
    }
    static func source(synthetic: Bool = false) throws -> CameraSource {
        let source = try CameraSource(configuration: .init(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false))
        source._detachNativeNotificationsForTesting()
        if synthetic { source._setStateForTesting(.running) }
        return source
    }
    static func frame(_ seconds: Double = 0) throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess, let buffer else { throw CameraPhotoCaptureError.missingResource }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetBytesPerRow(buffer) * 64)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 60_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { throw CameraPhotoCaptureError.missingResource }
        return sample
    }
    static func jpeg() throws -> Data {
        let sample = try frame()
        guard let data = CIContext(options: nil).jpegRepresentation(of: CIImage(cvPixelBuffer: CMSampleBufferGetImageBuffer(sample)!), colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else { throw CameraPhotoCaptureError.missingResource }
        return data
    }
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func previewLifecycle() async throws {
        for mode in [CameraPreviewController.Mode.raw, .processed] {
            for controls in [false, true] {
                let source = try source()
                let preview = CameraPreviewController(source: source, mode: mode, controlsSourceLifecycle: controls)
                preview.start()
                source._drainSessionQueueForTesting()
                try require((source.state != .idle) == controls, "预览开始没有遵守源所有权")
                preview.stop()
            }
        }
        for controls in [false, true] {
            let source = try source(synthetic: true)
            let preview = CameraPreviewController(source: source, mode: .raw, controlsSourceLifecycle: controls)
            preview.pause()
            source._drainSessionQueueForTesting()
            try require(source.isPaused == controls, "raw 暂停所有权错误")
            preview.resume()
            source._drainSessionQueueForTesting()
            try require(!source.isPaused, "raw 未恢复源")
            preview.stop()
            source._drainSessionQueueForTesting()
            try require(source.state == (controls ? .stopped : .running), "raw 停止所有权错误")
            source.stop()
        }
    }

    static func recordingLimits() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let limit = CMTime(value: 1, timescale: 10)
        let configuration = CameraCaptureConfiguration(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false,
            video: .init(dimensions: CGSize(width: 64, height: 64), maximumCaptureDuration: limit))
        let controller = try CameraRecordingController(configuration: configuration, outputURL: root.appendingPathComponent("controller.mp4"))
        let pipeline = try RecordingPipeline(configuration: configuration, outputURL: root.appendingPathComponent("pipeline.mp4"))
        let source = try CameraSource(configuration: configuration)
        let generic = try CameraRecordingController(source: source, outputURL: root.appendingPathComponent("generic.mp4"))
        let engine = try CameraEngine(configuration: configuration)
        let standard = try engine.makeRecordingController(outputURL: root.appendingPathComponent("engine.mp4"))
        let sharedEngine = try CameraEngine(configuration: configuration)
        let shared = try sharedEngine.startSharedRecording(outputURL: root.appendingPathComponent("shared.mp4"), previewSink: PreviewSink(frameHandler: { _ in }))
        for sink in [controller.recorderSink, pipeline.recorderSink, generic.recorderSink, standard.recorderSink, shared.recorderSink] {
            try require(sink.maximumDuration == limit, "录制入口遗漏最大时长")
        }
        for index in 0..<3 {
            let sample = try frame(Double(index) / 30)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.recorderSink.consume(SampleBufferFrame(sampleBuffer: sample)) { continuation.resume(with: $0) }
            }
        }
        try await wait("实际最大时长终态") { controller.state == .finished }
        try require((controller.recordedClip?.duration.seconds ?? 0) >= limit.seconds, "录制未达到正确结束边界")
        controller.cancel(); pipeline.cancel(); generic.cancel(); engine.cancel(); sharedEngine.cancel()
    }

    static func initializationOwner() async throws {
        let session = RecoveryPresetSession()
        let owner = CameraSessionOwner.shared(for: session)
        let key = DispatchSpecificKey<Bool>()
        owner.queue.setSpecific(key: key, value: true)
        let writes = RecoveryValue<[Bool]>([])
        session.writeObserver = { writes.update { $0.append(DispatchQueue.getSpecific(key: key) == true) } }
        let entered = RecoveryValue(false)
        let release = DispatchSemaphore(value: 0)
        owner.queue.async {
            session.beginConfiguration()
            entered.update { $0 = true }
            _ = release.wait(timeout: .now() + 5)
            session.commitConfiguration()
        }
        defer { release.signal() }
        try await wait("原生配置窗口") { entered.value }
        let created = RecoveryValue<CameraSource?>(nil)
        let failure = RecoveryValue<String?>(nil)
        DispatchQueue.global().async {
            do {
                let source = try CameraSource(session: session, configuration: .init(captureMode: .videoWithoutAudio, automaticallyRequestsAuthorization: false))
                source._detachNativeNotificationsForTesting()
                created.update { $0 = source }
            } catch { failure.update { $0 = String(describing: error) } }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        try require(created.value == nil && writes.value.isEmpty, "初始化越过正在执行的配置事务")
        release.signal()
        try await wait("构造完成") { created.value != nil || failure.value != nil }
        try require(failure.value == nil && !writes.value.isEmpty && writes.value.allSatisfy { $0 }, "preset 写入未使用共享 owner")
    }

    static func positionSwitch() async throws {
        let source = try source()
        source._queuePositionSwitchForTesting(.front)
        source._drainSessionQueueForTesting()
        try require(source.state == .idle && source.currentPosition == .front && source.session.inputs.isEmpty, "未建图切镜改变运行态或建立了半套输入")
        source._setStateForTesting(.running)
        let entered = RecoveryValue(false)
        let release = DispatchSemaphore(value: 0)
        source.sessionOwner.queue.async { entered.update { $0 = true }; _ = release.wait(timeout: .now() + 5) }
        defer { release.signal() }
        try await wait("切镜排队窗口") { entered.value }
        source._queuePositionSwitchForTesting(.back)
        source.stop()
        release.signal()
        source._drainSessionQueueForTesting()
        try await wait("停机交接") { !source._terminalHandoffForTesting.isPending }
        try require(source.state == .stopped && source.currentPosition == .front, "过期切镜影响已停止运行")
        source._setStateForTesting(.running)
        try require(source.state == .running && source.currentPosition == .front, "过期切镜影响新运行")
        source.stop()
    }

    static func arResume() throws {
        #if canImport(ARKit)
        let counts = RecoveryValue((runs: 0, pauses: 0))
        let source = ARFrameSource(configuration: .init(runHandler: { _ in counts.update { $0.runs += 1 } }, pauseHandler: { _ in counts.update { $0.pauses += 1 } }))
        source.resume()
        try require(!source.isRunning && counts.value.runs == 0, "AR 未开始就恢复")
        source.start()
        for _ in 0..<3 { source.pause(); source.pause(); source.resume(); source.resume() }
        try require(counts.value.runs == 4 && counts.value.pauses == 3 && source.isRunning, "AR 恢复未执行宿主操作或重复执行")
        source.stop(); source.resume()
        try require(!source.isRunning && counts.value.runs == 4, "AR 停止后被迟到恢复唤醒")
        let resumes = RecoveryValue(0)
        let explicit = ARFrameSource(configuration: .init(runHandler: { _ in resumes.update { $0 += 100 } }, resumeHandler: { _ in resumes.update { $0 += 1 } }))
        explicit.start(); explicit.pause(); explicit.resume()
        try require(resumes.value == 101, "AR 显式恢复错误地重跑了冷启动")
        explicit.stop()
        let noHandlers = ARFrameSource()
        noHandlers.start(); noHandlers.pause(); noHandlers.resume()
        try require(noHandlers.isRunning, "空 handler 过滤模式被破坏")
        noHandlers.stop()
        #endif
    }

    static func observerRoutes() async throws {
        let source = try source(synthetic: true)
        source._emitForTesting(sampleBuffer: try frame(), mediaType: .video)
        try require(source._observerIngressSnapshotForTesting.highWaterMark == 0, "空观察路线仍占用槽位")
        let observer = RecoveryDelegate()
        let handlerCalls = RecoveryValue(0)
        source.addMediaSourceDelegate(observer, delivery: .main)
        source.frameHandler = { _ in handlerCalls.update { $0 += 1 } }
        source._emitForTesting(sampleBuffer: try frame(1), mediaType: .video)
        try await wait("主线程观察者") { observer.frames.value == 1 && handlerCalls.value == 1 }
        try require(observer.mainThread.value, "主线程回调执行域变化")
        source.removeMediaSourceDelegate(observer)
        source.frameHandler = nil
        source.stop(); source._drainSessionQueueForTesting()
        try await wait("路由终态") { !source._terminalHandoffForTesting.isPending }
        source._setStateForTesting(.running)
        let processing = RecoveryDelegate()
        source.addMediaSourceDelegate(processing, delivery: .processing)
        source._emitForTesting(sampleBuffer: try frame(2), mediaType: .video)
        try await wait("处理路线") { processing.frames.value == 1 }
        try require(source._observerIngressSnapshotForTesting.highWaterMark == 0 && !processing.mainThread.value, "处理路线多余投递主线程")
        try require(observer.frames.value == 1 && handlerCalls.value == 1, "移除订阅后仍交付")
        source.stop()
    }

    static func legacyPhotoTerminal() async throws {
        let source = try source(synthetic: true)
        let observer = RecoveryDelegate()
        source.delegate = observer
        let first = RecoveryValue(0)
        let next = RecoveryValue(0)
        source.photoCaptureHandler = { _ in first.update { $0 += 1 } }
        let resource = try CameraPhotoCaptureResource(encodedData: jpeg(), metadata: [:], origin: .nativePhoto)
        let result = CameraPhotoCaptureResult(resource: resource)
        source._beginLegacyPhotoForTesting(1)
        source.photoCaptureHandler = { _ in next.update { $0 += 1 } }
        source._stageLegacyPhotoForTesting(1, result: .success(result))
        await Task.yield()
        try require(first.value == 0, "处理完成提前发布成功")
        source.stop(); source._drainSessionQueueForTesting()
        source._finishLegacyPhotoForTesting(1)
        source._finishLegacyPhotoForTesting(1)
        try await wait("已受理照片完成") { first.value == 1 }
        source._beginLegacyPhotoForTesting(2)
        source._stageLegacyPhotoForTesting(2, result: .success(result))
        source._finishLegacyPhotoForTesting(2, error: CameraPhotoCaptureError.captureFailed("最终失败"))
        source._beginLegacyPhotoForTesting(3)
        source._finishLegacyPhotoForTesting(3, error: CameraPhotoCaptureError.captureTimedOut)
        source._stageLegacyPhotoForTesting(3, result: .success(result))
        source._finishLegacyPhotoForTesting(3)
        try await wait("最终失败与超时") { observer.failures.value == 2 }
        try require(next.value == 0 && first.value == 1, "终态失败或冻结回调合同变化")
    }

    static func nativeCancellation() async throws {
        for completionFirst in [false, true] { try await nativeCancellation(completionFirst: completionFirst) }
    }

    private static func nativeCancellation(completionFirst: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(synthetic: true)
        let sourceBox = RecoveryValue(source)
        let request = CameraPhotoCaptureRequest(format: .jpeg, includesLivePhoto: true, outputDirectory: root)
        let state = CameraPhotoTask<CameraPhotoCaptureArtifact>()
        let delegate = RecoveryValue<NativePhotoRequestDelegate?>(nil)
        let pending = Task {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if state.begin(continuation) {
                        let item = sourceBox.value._registerPhotoTaskForTesting(request, uniqueID: 100, task: state)
                        delegate.update { $0 = item }
                    }
                }
            } onCancel: { state.cancel() }
        }
        defer { pending.cancel() }
        try await wait("原生请求注册") { delegate.value != nil }
        try require(source._nativePhotoRequestCountForTesting == 1, "请求未占用槽位")
        let bytes = try jpeg()
        delegate.value!.receivePhoto(data: bytes, metadata: [:], isRaw: false, resolvedFlashEnabled: false, timestamp: 0)
        try require(!((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).isEmpty, "照片夹具没有落盘")
        let completionEntered = RecoveryValue(false)
        let completionReturned = RecoveryValue(false)
        let completionRelease = DispatchSemaphore(value: 0)
        defer { completionRelease.signal() }
        if completionFirst {
            delegate.value!._beforeCompletionForTesting = { completionEntered.update { $0 = true }; _ = completionRelease.wait(timeout: .now() + 5) }
            let captured = delegate.value!
            DispatchQueue.global().async { captured.finishCapture(); completionReturned.update { $0 = true } }
            try await wait("原生结果冻结、尚未交付") { completionEntered.value }
        }
        pending.cancel()
        do { _ = try await pending.value; throw CameraPhotoCaptureError.missingResource }
        catch is CancellationError {}
        source._drainSessionQueueForTesting()
        try require(source._nativePhotoRequestCountForTesting == 0, "取消未释放逻辑槽位")
        if completionFirst {
            completionRelease.signal()
            try await wait("被取消的已冻结结果清理") { completionReturned.value }
        }
        try require(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty, "取消未清理已写照片")
        let movie = request.resourceURL(state.resourceID, suffix: ".mov")
        try Data([1, 2, 3]).write(to: movie)
        delegate.value!.receiveMovie(at: movie, keyTime: .zero, error: nil)
        delegate.value!.finishCapture()
        try require(!FileManager.default.fileExists(atPath: movie.path), "迟到电影文件泄漏")
        let release = RecoveryValue<CheckedContinuation<Void, Never>?>(nil)
        let preCancelled = Task {
            await withCheckedContinuation { continuation in release.update { $0 = continuation } }
            return try await sourceBox.value.capturePhoto(request: request)
        }
        defer { release.value?.resume() }
        try await wait("预取消任务屏障") { release.value != nil }
        preCancelled.cancel()
        let waiting = release.value
        release.update { $0 = nil }
        waiting?.resume()
        do { _ = try await preCancelled.value; throw CameraPhotoCaptureError.missingResource }
        catch is CancellationError {}
        try require(source._nativePhotoRequestCountForTesting == 0, "预取消请求进入原生队列")
        source.stop()
    }

    static func nativeWriteRace() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = CameraPhotoCaptureRequest(format: .jpeg, outputDirectory: root)
        let id = UUID()
        let resultCount = RecoveryValue(0)
        let delegate = NativePhotoRequestDelegate(request: request, hardwareObservation: nil, resourceID: id) { _ in resultCount.update { $0 += 1 } }
        let entered = RecoveryValue(false)
        let complete = RecoveryValue(false)
        let cancelled = RecoveryValue(false)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        delegate._beforePublishingPhotoForTesting = { entered.update { $0 = true }; _ = release.wait(timeout: .now() + 5) }
        let bytes = try jpeg()
        DispatchQueue.global().async {
            delegate.receivePhoto(data: bytes, metadata: [:], isRaw: false, resolvedFlashEnabled: false, timestamp: 0)
            complete.update { $0 = true }
        }
        try await wait("照片文件已写入、尚未发布") { entered.value }
        DispatchQueue.global().async { delegate.cancel(); cancelled.update { $0 = true } }
        try await wait("取消不等待文件发布锁") { cancelled.value }
        release.signal()
        try await wait("未发布文件清理") { complete.value }
        try require(!FileManager.default.fileExists(atPath: request.resourceURL(id, suffix: "-processed.jpg").path) && resultCount.value == 0, "取消与文件发布竞争泄漏结果")
        let timeout = NativePhotoRequestDelegate(request: .init(id: request.id, format: .jpeg, includesLivePhoto: true, outputDirectory: root), hardwareObservation: nil, resourceID: id) { _ in }
        timeout.terminate(.captureTimedOut)
        let movie = request.resourceURL(id, suffix: ".mov")
        try Data([1]).write(to: movie)
        timeout.receiveMovie(at: movie, keyTime: .zero, error: nil)
        try require(!FileManager.default.fileExists(atPath: movie.path), "超时后电影文件泄漏")
    }

    static func nativeResources() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = CameraPhotoCaptureRequest(format: .jpeg, includesLivePhoto: true, outputDirectory: root)
        let firstID = UUID()
        let secondID = UUID()
        let first = NativePhotoRequestDelegate(request: request, hardwareObservation: nil, resourceID: firstID, finish: { _ in })
        let result = RecoveryValue<CameraPhotoCaptureArtifact?>(nil)
        let second = NativePhotoRequestDelegate(request: request, hardwareObservation: nil, resourceID: secondID) { response in
            if case .success(let artifact) = response { result.update { $0 = artifact } }
        }
        let bytes = try jpeg()
        first.receivePhoto(data: bytes, metadata: [:], isRaw: false, resolvedFlashEnabled: false, timestamp: 0)
        second.receivePhoto(data: bytes, metadata: [:], isRaw: false, resolvedFlashEnabled: false, timestamp: 0)
        first.cancel()
        let secondURL = request.resourceURL(secondID, suffix: "-processed.jpg")
        try require(FileManager.default.fileExists(atPath: secondURL.path), "旧尝试取消删除了新尝试文件")
        second.finishCapture(error: .captureFailed("电影失败"))
        guard let artifact = result.value else { throw CameraPhotoCaptureError.missingResource }
        try require(artifact.captureFailure != nil && artifact.processedPhoto?.fileURL == secondURL && artifact.processedPhoto?.data == nil, "部分资源恢复合同变化")
        second.cancel()
        try require(FileManager.default.fileExists(atPath: secondURL.path), "完成后的取消删除了已交付文件")
        NativePhotoRequestDelegate.discard(artifact, request: request, resourceID: secondID)
        try require(!FileManager.default.fileExists(atPath: secondURL.path), "未交付结果清理失效")
    }
}

private final class RecoveryValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
}
private final class RecoveryPresetSession: AVCaptureSession, @unchecked Sendable {
    var writeObserver: (() -> Void)?
    override var sessionPreset: AVCaptureSession.Preset {
        get { super.sessionPreset }
        set { writeObserver?(); super.sessionPreset = newValue }
    }
}
private final class RecoveryDelegate: MediaSourceDelegate {
    let frames = RecoveryValue(0)
    let failures = RecoveryValue(0)
    let mainThread = RecoveryValue(false)
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {
        frames.update { $0 += 1 }
        mainThread.update { $0 = Thread.isMainThread }
    }
    func mediaSource(_ source: MediaSource, didFail error: Error) { failures.update { $0 += 1 } }
    func mediaSourceDidFinish(_ source: MediaSource) {}
}
#endif
