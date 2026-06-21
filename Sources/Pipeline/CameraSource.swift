//
//  CameraSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public final class CameraSource: NSObject, MediaSource, MediaFrameSourceNode {
    public struct Summary {
        public let state: CameraSessionState
        public let position: CameraPosition
        public let authorizationStatus: CameraAuthorizationStatus
        public let isPaused: Bool
        public let captureMode: CameraCaptureMode
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastMediaType: String?

        public var summaryText: String {
            var text = "state \(state) · position \(position) · auth \(authorizationStatus) · paused \(isPaused ? "yes" : "no") · mode \(captureMode)"
            if let lastFrameIndex {
                text += " · frame \(lastFrameIndex)"
            }
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let lastMediaType {
                text += " · mediaType \(lastMediaType)"
            }
            return text
        }
    }

    public enum MetadataKey {
        public static let mediaType = "kakapos.camera.media-type"
        public static let cameraPosition = "kakapos.camera.position"
        public static let sessionState = "kakapos.camera.session-state"
        public static let deviceOrientation = "kakapos.camera.device-orientation"
        public static let mirrored = "kakapos.camera.mirrored"
    }

    public weak var delegate: MediaSourceDelegate?
    public var session: AVCaptureSession { realtime.captureSession ?? fallbackSession }
    public var previewLayer: AVCaptureVideoPreviewLayer { realtime.previewLayer }
    public private(set) var isPaused: Bool = false
    public private(set) var state: CameraSessionState = .idle
    public private(set) var currentPosition: CameraPosition
    public private(set) var authorizationStatus: CameraAuthorizationStatus
    public private(set) var configuration: CameraSourceConfiguration
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?
    public var photoCaptureHandler: ((CameraPhotoCaptureResult) -> Void)?
    public var authorizationStatusChangedHandler: ((CameraAuthorizationStatus) -> Void)?
    public var summary: Summary {
        Summary(
            state: state,
            position: currentPosition,
            authorizationStatus: authorizationStatus,
            isPaused: isPaused,
            captureMode: configuration.captureMode,
            lastFrameIndex: frameIndex > 0 ? frameIndex : nil,
            lastPresentationTime: lastPresentationTime,
            lastMediaType: lastMediaType
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    private let queue = DispatchQueue(label: "com.condy.kakapos.camera-source")
    private let realtime: KakaposRealtime
    private let fallbackSession = AVCaptureSession()
    private let outputNode = MediaOutputNode()
    private var lifecycle: CameraSessionLifecycle
    private var frameIndex: Int64 = 0
    private var lastPresentationTime: CMTime?
    private var lastMediaType: String?
    private var currentOrientation: AVCaptureVideoOrientation = .portrait
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true

    public init(configuration: CameraSourceConfiguration = CameraSourceConfiguration()) throws {
        self.realtime = KakaposRealtime()
        self.configuration = configuration
        self.currentPosition = configuration.preferredPosition
        self.authorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.lifecycle = CameraSessionLifecycle(position: configuration.preferredPosition, authorizationStatus: Self.authorizationStatus(for: configuration.captureMode))
        super.init()
        configure()
    }

    public convenience init(sessionPreset: AVCaptureSession.Preset = .high, position: AVCaptureDevice.Position = .back) throws {
        try self.init(
            configuration: CameraSourceConfiguration(
                preferredPosition: Self.cameraPosition(from: position),
                video: CameraVideoConfiguration(sessionPreset: sessionPreset)
            )
        )
    }

    public func start() {
        resetFrameAcceptance()
        let status = Self.authorizationStatus(for: configuration.captureMode)
        authorizationStatus = status
        frameIndex = 0
        lastPresentationTime = nil
        lastMediaType = nil
        publish(.authorizationChanged(status))
        if status != .authorized {
            guard configuration.automaticallyRequestsAuthorization, status == .notDetermined else {
                notifyAuthorizationFailure()
                return
            }
            requestRequiredAuthorizations { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.start()
                } else {
                    self.notifyAuthorizationFailure()
                }
            }
            return
        }
        publish(.startRequested)
        queue.async {
            do {
                try self.realtime.start()
            } catch {
                self.publish(.runtimeError(isRecoverable: false, description: error.localizedDescription))
                DispatchQueue.main.async {
                    self.delegate?.mediaSource(self, didFail: error)
                }
            }
        }
    }

    public func pause() {
        isPaused = true
        publish(.pauseRequested)
    }

    public func resume() {
        isPaused = false
        publish(.resumeRequested)
    }

    public func stop() {
        rejectFurtherFrames()
        queue.async {
            self.realtime.stop()
        }
    }

    public func cancel() {
        rejectFurtherFrames()
        stop()
    }

    @discardableResult
    public func switchCameraPosition() -> Bool {
        let nextPosition: CameraPosition = currentPosition == .back ? .front : .back
        return switchCameraPosition(to: nextPosition)
    }

    @discardableResult
    public func switchCameraPosition(to position: CameraPosition) -> Bool {
        guard position != .unspecified else { return false }
        publish(.positionSwitchRequested(position))
        realtime.flipCaptureDevicePosition()
        applyMirroring(for: position)
        publish(.positionChanged(position))
        return true
    }

    public func capturePhoto() {
        realtime.capturePhoto()
    }

    public func capturePhotoFromCurrentFrame() {
        realtime.capturePhotoFromVideo()
    }

    public static func authorizationStatus(for captureMode: CameraCaptureMode) -> CameraAuthorizationStatus {
        let statuses = captureMode.requestedMediaTypes.map { authorizationStatus(for: $0) }
        if statuses.contains(.denied) {
            return .denied
        }
        if statuses.allSatisfy({ $0 == .authorized }) {
            return .authorized
        }
        return .notDetermined
    }

    public static func authorizationStatus(for mediaType: AVMediaType) -> CameraAuthorizationStatus {
        switch KakaposRealtime.authorizationStatus(forMediaType: mediaType) {
        case .authorized:
            return .authorized
        case .notAuthorized:
            return .denied
        case .notDetermined:
            return .notDetermined
        }
    }

    public static func requestAuthorization(for mediaType: AVMediaType, completion: @escaping (CameraAuthorizationStatus) -> Void) {
        KakaposRealtime.requestAuthorization(forMediaType: mediaType) { _, status in
            switch status {
            case .authorized:
                completion(.authorized)
            case .notAuthorized:
                completion(.denied)
            case .notDetermined:
                completion(.notDetermined)
            }
        }
    }

    private func configure() {
        realtime.delegate = self
        realtime.videoDelegate = self
        realtime.deviceDelegate = self
        realtime.photoDelegate = self
        realtime.captureMode = realtimeCaptureMode(for: configuration.captureMode)
        realtime.devicePosition = avDevicePosition(from: configuration.preferredPosition)
        realtime.previewLayer.videoGravity = configuration.previewGravity
        configuration.video.apply(to: realtime.videoConfiguration)
        configuration.photo.apply(to: realtime.photoConfiguration)
        realtime.rawVideoSampleBufferHandler = { [weak self] sampleBuffer, _ in
            self?.emit(sampleBuffer: sampleBuffer, mediaType: .video)
        }
        realtime.rawAudioSampleBufferHandler = { [weak self] sampleBuffer, _ in
            self?.emit(sampleBuffer: sampleBuffer, mediaType: .audio)
        }
        applyMirroring(for: configuration.preferredPosition)
    }

    private func emit(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        guard canAcceptFrames() else { return }
        guard !isPaused else { return }
        frameIndex += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        lastPresentationTime = presentationTime
        lastMediaType = mediaType.rawValue
        var frame = MediaFrame(
            sampleBuffer: sampleBuffer,
            metadata: FrameMetadata(
                presentationTime: presentationTime,
                duration: duration.isValid ? duration : nil,
                sourceTime: presentationTime,
                frameIndex: frameIndex,
                userInfo: [
                    MetadataKey.mediaType: mediaType.rawValue,
                    MetadataKey.cameraPosition: String(describing: currentPosition),
                    MetadataKey.sessionState: String(describing: state),
                    MetadataKey.deviceOrientation: String(describing: currentOrientation),
                    MetadataKey.mirrored: configuration.effectiveMirroringValue(for: currentPosition)
                ]
            )
        )
        frame.metadata.frameIndex = frameIndex
        DispatchQueue.main.async {
            self.delegate?.mediaSource(self, didOutput: frame)
            self.outputNode.transmit(frame) { _ in }
        }
    }

    func _emitForTesting(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        emit(sampleBuffer: sampleBuffer, mediaType: mediaType)
    }

    func _setStateForTesting(_ state: CameraSessionState) {
        self.state = state
    }

    private func publish(_ action: CameraLifecycleAction) {
        guard let event = lifecycle.handle(action) else { return }
        state = lifecycle.state
        currentPosition = lifecycle.position
        authorizationStatus = lifecycle.authorizationStatus
        DispatchQueue.main.async {
            self.sessionEventHandler?(event)
            if case .authorizationChanged(let status) = event {
                self.authorizationStatusChangedHandler?(status)
            }
        }
    }

    private static func cameraPosition(from position: AVCaptureDevice.Position) -> CameraPosition {
        switch position {
        case .front:
            return .front
        case .back:
            return .back
        default:
            return .unspecified
        }
    }

    private func avDevicePosition(from position: CameraPosition) -> AVCaptureDevice.Position {
        switch position {
        case .front:
            return .front
        case .back:
            return .back
        case .unspecified:
            return .unspecified
        }
    }

    private func realtimeCaptureMode(for captureMode: CameraCaptureMode) -> KakaposRealtimeCaptureMode {
        switch captureMode {
        case .video:
            return .video
        case .videoWithoutAudio:
            return .videoWithoutAudio
        case .photo:
            return .photo
        }
    }

    private func requestRequiredAuthorizations(completion: @escaping (Bool) -> Void) {
        let mediaTypes = configuration.requestedMediaTypes
        guard !mediaTypes.isEmpty else {
            completion(true)
            return
        }
        let group = DispatchGroup()
        var allGranted = true
        for mediaType in mediaTypes {
            let status = Self.authorizationStatus(for: mediaType)
            if status == .authorized {
                continue
            }
            group.enter()
            Self.requestAuthorization(for: mediaType) { status in
                if status != .authorized {
                    allGranted = false
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(allGranted)
        }
    }

    private func notifyAuthorizationFailure() {
        publish(.authorizationChanged(Self.authorizationStatus(for: configuration.captureMode)))
        let error = KakaposRealtimeError.authorization
        DispatchQueue.main.async {
            self.delegate?.mediaSource(self, didFail: error)
        }
    }

    private func applyMirroring(for position: CameraPosition) {
        switch configuration.mirroringMode {
        case .off:
            realtime.mirroringMode = .off
        case .on:
            realtime.mirroringMode = .on
        case .automatic:
            realtime.mirroringMode = position == .front ? .auto : .off
        }
    }

    private func resetFrameAcceptance() {
        lifecycleLock.lock()
        acceptsFrames = true
        lifecycleLock.unlock()
    }

    private func rejectFurtherFrames() {
        lifecycleLock.lock()
        acceptsFrames = false
        lifecycleLock.unlock()
    }

    private func canAcceptFrames() -> Bool {
        lifecycleLock.lock()
        let result = acceptsFrames
        lifecycleLock.unlock()
        return result
    }

    private func emitPhotoResult(photoDictionary: [String: Any], isFromCurrentFrame: Bool) {
        let data =
            photoDictionary[KakaposRealtimePhotoFileDataKey] as? Data ??
            photoDictionary[KakaposRealtimePhotoJPEGKey] as? Data ??
            photoDictionary[KakaposRealtimePhotoCroppedJPEGKey] as? Data
        let metadata = photoDictionary[KakaposRealtimePhotoMetadataKey] as? [String: Any] ?? [:]
        let result = CameraPhotoCaptureResult(data: data, metadata: metadata, isFromCurrentFrame: isFromCurrentFrame)
        DispatchQueue.main.async {
            self.photoCaptureHandler?(result)
        }
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    public func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }
}

extension CameraSource: KakaposRealtimeDelegate {
    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoConfiguration videoConfiguration: KakaposRealtimeVideoConfiguration) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateAudioConfiguration audioConfiguration: KakaposRealtimeAudioConfiguration) {}

    public func kakaposRealtimeSessionWillStart(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeSessionDidStart(_ kakaposRealtime: KakaposRealtime) {
        publish(.didStartRunning)
    }

    public func kakaposRealtimeSessionDidStop(_ kakaposRealtime: KakaposRealtime) {
        publish(.didStopRunning)
        delegate?.mediaSourceDidFinish(self)
    }

    public func kakaposRealtimeSessionWasInterrupted(_ kakaposRealtime: KakaposRealtime) {
        publish(.wasInterrupted)
    }

    public func kakaposRealtimeSessionInterruptionEnded(_ kakaposRealtime: KakaposRealtime) {
        publish(.interruptionEnded)
    }

    public func kakaposRealtimeCaptureModeWillChange(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeCaptureModeDidChange(_ kakaposRealtime: KakaposRealtime) {}
}

extension CameraSource: KakaposRealtimeVideoDelegate {
    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoZoomFactor videoZoomFactor: Float) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessRawVideoSampleBuffer sampleBuffer: CMSampleBuffer, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessFrame frame: AnyObject, timestamp: TimeInterval, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupVideoInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupAudioInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didStartClipInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteClip clip: KakaposRealtimeClip, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompletePhotoCaptureFromVideoFrame photoDict: [String : Any]?) {
        guard let photoDict else { return }
        emitPhotoResult(photoDictionary: photoDict, isFromCurrentFrame: true)
    }
}

extension CameraSource: KakaposRealtimeDeviceDelegate {
    public var kakaposRealtimeCurrentDeviceOrientation: (() -> AVCaptureVideoOrientation)? {
        { [weak self] in
            self?.currentOrientation ?? .portrait
        }
    }

    public func kakaposRealtimeDevicePositionWillChange(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeDevicePositionDidChange(_ kakaposRealtime: KakaposRealtime) {
        let position = Self.cameraPosition(from: kakaposRealtime.devicePosition)
        applyMirroring(for: position)
        publish(.positionChanged(position))
    }

    public func kakaposRealtimeDeviceOrientationWillChange(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeDeviceOrientation deviceOrientation: KakaposRealtimeDeviceOrientation) {
        currentOrientation = deviceOrientation
    }

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeDeviceFormat deviceFormat: AVCaptureDevice.Format) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeCleanAperture cleanAperture: CGRect) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeLensPosition lensPosition: Float) {}

    public func kakaposRealtimeWillStartFocus(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeDidStopFocus(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeWillChangeExposure(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeDidChangeExposure(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeExposureDuration exposureDuration: CMTime) {}

    public func kakaposRealtimeWillChangeWhiteBalance(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeDidChangeWhiteBalance(_ kakaposRealtime: KakaposRealtime) {}
}

extension CameraSource: KakaposRealtimePhotoDelegate {
    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didFinishProcessingPhoto photo: AVCapturePhoto, photoDict: [String : Any], photoConfiguration: KakaposRealtimePhotoConfiguration) {
        emitPhotoResult(photoDictionary: photoDict, isFromCurrentFrame: false)
    }

    public func kakaposRealtimeDidCompletePhotoCapture(_ kakaposRealtime: KakaposRealtime) {}
}
#endif
