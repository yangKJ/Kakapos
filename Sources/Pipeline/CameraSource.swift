//
//  CameraSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreImage

#if canImport(UIKit) && !os(watchOS)
import UIKit

public enum CameraSourceError: Error, LocalizedError, Equatable {
    case authorizationDenied(requestedMediaTypes: [AVMediaType])
    case captureDeviceUnavailable(position: CameraPosition, preferredDeviceTypes: [CameraDeviceType])
    case cannotAddInput(AVMediaType)
    case cannotAddOutput(AVMediaType)
    case photoFrameUnavailable
    case cannotCapturePhoto

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied(let requestedMediaTypes):
            return "Camera authorization denied for \(requestedMediaTypes.map(\.rawValue).joined(separator: ", "))"
        case .captureDeviceUnavailable(let position, let preferredDeviceTypes):
            let types = preferredDeviceTypes.map(\.description).joined(separator: ", ")
            return "Camera device unavailable for position \(position) with preferred types [\(types)]"
        case .cannotAddInput(let mediaType):
            return "Cannot add \(mediaType.rawValue) capture input"
        case .cannotAddOutput(let mediaType):
            return "Cannot add \(mediaType.rawValue) capture output"
        case .photoFrameUnavailable:
            return "No current frame is available for photo capture"
        case .cannotCapturePhoto:
            return "Photo output is unavailable for capture"
        }
    }
}

public final class CameraSource: NSObject, MediaSource, MediaFrameSourceNode, MediaSourceSnapshotProviding {
    public struct Snapshot: Equatable {
        public let state: CameraSessionState
        public let position: CameraPosition
        public let authorizationStatus: CameraAuthorizationStatus
        public let isPaused: Bool
        public let captureMode: CameraCaptureMode
        public let deviceOrientation: AVCaptureVideoOrientation
        public let isMirrored: Bool
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastMediaType: String?
    }

    public struct Summary {
        public let state: CameraSessionState
        public let position: CameraPosition
        public let authorizationStatus: CameraAuthorizationStatus
        public let isPaused: Bool
        public let captureMode: CameraCaptureMode
        public let deviceOrientation: AVCaptureVideoOrientation
        public let isMirrored: Bool
        public let lastFrameIndex: Int64?
        public let lastPresentationTime: CMTime?
        public let lastMediaType: String?

        public var summaryText: String {
            var text = "state \(state) · position \(position) · auth \(authorizationStatus) · paused \(isPaused ? "yes" : "no") · mode \(captureMode) · orientation \(deviceOrientation) · mirrored \(isMirrored ? "yes" : "no")"
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
    public let session: AVCaptureSession
    public let previewLayer: AVCaptureVideoPreviewLayer
    public private(set) var isPaused: Bool = false
    public private(set) var state: CameraSessionState = .idle
    public private(set) var currentPosition: CameraPosition
    public private(set) var authorizationStatus: CameraAuthorizationStatus
    public private(set) var configuration: CameraSourceConfiguration
    public var frameHandler: ((MediaFrame) -> Void)?
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?
    public var photoCaptureHandler: ((CameraPhotoCaptureResult) -> Void)?
    public var authorizationStatusChangedHandler: ((CameraAuthorizationStatus) -> Void)?

    public var snapshot: Snapshot {
        Snapshot(
            state: state,
            position: currentPosition,
            authorizationStatus: authorizationStatus,
            isPaused: isPaused,
            captureMode: configuration.captureMode,
            deviceOrientation: currentOrientation,
            isMirrored: configuration.effectiveMirroringValue(for: currentPosition),
            lastFrameIndex: frameIndex > 0 ? frameIndex : nil,
            lastPresentationTime: lastPresentationTime,
            lastMediaType: lastMediaType
        )
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
        return Summary(
            state: currentSnapshot.state,
            position: currentSnapshot.position,
            authorizationStatus: currentSnapshot.authorizationStatus,
            isPaused: currentSnapshot.isPaused,
            captureMode: currentSnapshot.captureMode,
            deviceOrientation: currentSnapshot.deviceOrientation,
            isMirrored: currentSnapshot.isMirrored,
            lastFrameIndex: currentSnapshot.lastFrameIndex,
            lastPresentationTime: currentSnapshot.lastPresentationTime,
            lastMediaType: currentSnapshot.lastMediaType
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public var sourceSnapshot: MediaSourceSnapshot {
        let currentSnapshot = snapshot
        return MediaSourceSnapshot(
            stateDescription: String(describing: currentSnapshot.state),
            lastFrameIndex: currentSnapshot.lastFrameIndex,
            lastPresentationTime: currentSnapshot.lastPresentationTime,
            lastSourceTime: currentSnapshot.lastPresentationTime,
            details: [
                "sessionState": String(describing: currentSnapshot.state),
                "position": String(describing: currentSnapshot.position),
                "auth": String(describing: currentSnapshot.authorizationStatus),
                "paused": currentSnapshot.isPaused ? "yes" : "no",
                "mode": String(describing: currentSnapshot.captureMode),
                "orientation": String(describing: currentSnapshot.deviceOrientation),
                "mirrored": currentSnapshot.isMirrored ? "yes" : "no",
                "mediaType": currentSnapshot.lastMediaType ?? "n/a"
            ]
        )
    }

    private let sessionQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.session")
    private let videoOutputQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.video")
    private let audioOutputQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.audio")
    private let photoQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.photo")
    private let outputNode = MediaOutputNode()
    private var lifecycle: CameraSessionLifecycle
    private var frameIndex: Int64 = 0
    private var lastPresentationTime: CMTime?
    private var lastMediaType: String?
    private var currentOrientation: AVCaptureVideoOrientation = .portrait
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext(options: nil)
    private var notificationObservers: [NSObjectProtocol] = []
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false
    private var lastVideoPixelBuffer: CVPixelBuffer?
    private var lastVideoSampleBuffer: CMSampleBuffer?

    public init(configuration: CameraSourceConfiguration = CameraSourceConfiguration()) throws {
        self.session = AVCaptureSession()
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        self.configuration = configuration
        self.currentPosition = configuration.preferredPosition
        self.authorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.lifecycle = CameraSessionLifecycle(
            position: configuration.preferredPosition,
            authorizationStatus: Self.authorizationStatus(for: configuration.captureMode)
        )
        super.init()
        configurePreviewLayer()
        applySessionPreset()
        updateCurrentOrientation()
        startObservingNotifications()
    }

    deinit {
        stopObservingNotifications()
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
        refreshRuntimeStateForStart()
        let status = Self.authorizationStatus(for: configuration.captureMode)
        authorizationStatus = status
        publish(.authorizationChanged(status))
        guard status == .authorized else {
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
        sessionQueue.async {
            do {
                try self.ensureSessionConfigured()
                self.applyCurrentConnections()
                if !self.session.isRunning {
                    self.session.startRunning()
                } else {
                    self.publish(.didStartRunning)
                }
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
        sessionQueue.async {
            self.lastVideoSampleBuffer = nil
            self.lastVideoPixelBuffer = nil
            if self.session.isRunning {
                self.session.stopRunning()
            } else {
                self.publish(.didStopRunning)
                DispatchQueue.main.async {
                    self.delegate?.mediaSourceDidFinish(self)
                }
            }
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
        guard findVideoDevice(position: position) != nil else { return false }
        publish(.positionSwitchRequested(position))
        sessionQueue.async {
            do {
                try self.replaceVideoInput(position: position)
                self.applyMirroring(for: position)
                self.publish(.positionChanged(position))
            } catch {
                self.publish(.runtimeError(isRecoverable: false, description: error.localizedDescription))
                DispatchQueue.main.async {
                    self.delegate?.mediaSource(self, didFail: error)
                }
            }
        }
        return true
    }

    public func capturePhoto() {
        sessionQueue.async {
            guard self.isSessionConfigured, self.session.isRunning else {
                self.capturePhotoFromCurrentFrame()
                return
            }
            guard self.photoOutput.connections.isEmpty == false else {
                DispatchQueue.main.async {
                    self.delegate?.mediaSource(self, didFail: CameraSourceError.cannotCapturePhoto)
                }
                return
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.flashMode = self.resolvedFlashMode()
            settings.isHighResolutionPhotoEnabled = self.configuration.photo.isHighResolutionEnabled
            if #available(iOS 13.0, *) {
                settings.photoQualityPrioritization = self.configuration.photo.photoQualityMode.avFoundationValue
            }
            if self.configuration.photo.generateThumbnail,
               let previewPixelType = settings.availablePreviewPhotoPixelFormatTypes.first {
                settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPixelType]
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    public func capturePhotoFromCurrentFrame() {
        photoQueue.async {
            guard let pixelBuffer = self.lastVideoPixelBuffer else {
                DispatchQueue.main.async {
                    self.delegate?.mediaSource(self, didFail: CameraSourceError.photoFrameUnavailable)
                }
                return
            }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let metadata = Self.attachmentsDictionary(from: self.lastVideoSampleBuffer)
            let data = self.ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: [:])
            let result = CameraPhotoCaptureResult(data: data, metadata: metadata, isFromCurrentFrame: true)
            DispatchQueue.main.async {
                self.photoCaptureHandler?(result)
            }
        }
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
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    public static func requestAuthorization(for mediaType: AVMediaType, completion: @escaping (CameraAuthorizationStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: mediaType) { granted in
            completion(granted ? .authorized : .denied)
        }
    }

    func _emitForTesting(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        emit(sampleBuffer: sampleBuffer, mediaType: mediaType)
    }

    func _setStateForTesting(_ state: CameraSessionState) {
        self.state = state
        self.isPaused = state == .paused
    }

    func _handleLifecycleActionForTesting(_ action: CameraLifecycleAction) {
        publish(action)
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

    private func refreshRuntimeStateForStart() {
        frameIndex = 0
        lastPresentationTime = nil
        lastMediaType = nil
        lastVideoSampleBuffer = nil
        lastVideoPixelBuffer = nil
        isPaused = false
        state = .idle
    }

    private func configurePreviewLayer() {
        previewLayer.videoGravity = configuration.previewGravity
    }

    private func applySessionPreset() {
        let preset = activeSessionPreset
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
    }

    private var activeSessionPreset: AVCaptureSession.Preset {
        switch configuration.captureMode {
        case .photo:
            return configuration.photo.sessionPreset
        case .video, .videoWithoutAudio:
            return configuration.video.sessionPreset
        }
    }

    private func ensureSessionConfigured() throws {
        guard !isSessionConfigured else { return }
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        applySessionPreset()
        try configureVideoInput(position: configuration.preferredPosition)
        try configureAudioInputIfNeeded()
        try configureVideoOutput()
        try configureAudioOutputIfNeeded()
        try configurePhotoOutput()
        applyCurrentConnections()
        isSessionConfigured = true
    }

    private func configureVideoInput(position: CameraPosition) throws {
        let resolvedPosition = position == .unspecified ? .back : position
        guard let device = findVideoDevice(position: resolvedPosition) else {
            throw CameraSourceError.captureDeviceUnavailable(
                position: resolvedPosition,
                preferredDeviceTypes: configuration.preferredDeviceTypes
            )
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSourceError.cannotAddInput(.video)
        }
        session.addInput(input)
        videoInput = input
        currentPosition = resolvedPosition
    }

    private func replaceVideoInput(position: CameraPosition) throws {
        let previousInput = videoInput
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        if let previousInput {
            session.removeInput(previousInput)
            videoInput = nil
        }
        do {
            try configureVideoInput(position: position)
            applyCurrentConnections()
        } catch {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                videoInput = previousInput
                currentPosition = Self.cameraPosition(from: previousInput.device.position)
                applyCurrentConnections()
            }
            throw error
        }
    }

    private func configureAudioInputIfNeeded() throws {
        guard configuration.captureMode.includesAudio else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraSourceError.cannotAddInput(.audio)
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSourceError.cannotAddInput(.audio)
        }
        session.addInput(input)
        audioInput = input
    }

    private func configureVideoOutput() throws {
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraSourceError.cannotAddOutput(.video)
        }
        session.addOutput(videoOutput)
    }

    private func configureAudioOutputIfNeeded() throws {
        guard configuration.captureMode.includesAudio else { return }
        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
        guard session.canAddOutput(audioOutput) else {
            throw CameraSourceError.cannotAddOutput(.audio)
        }
        session.addOutput(audioOutput)
    }

    private func configurePhotoOutput() throws {
        guard session.canAddOutput(photoOutput) else {
            throw CameraSourceError.cannotAddOutput(.video)
        }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = configuration.photo.isHighResolutionEnabled
    }

    private func findVideoDevice(position: CameraPosition) -> AVCaptureDevice? {
        let requestedPosition = avDevicePosition(from: position)
        let preferredTypes = configuration.preferredDeviceTypes
            .flatMap(\.avFoundationTypes)
        let deviceTypes = preferredTypes.isEmpty ? [AVCaptureDevice.DeviceType.builtInWideAngleCamera] : preferredTypes
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: requestedPosition
        )
        if let device = discoverySession.devices.first {
            return device
        }
        if requestedPosition != .unspecified {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: requestedPosition)
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func resolvedFlashMode() -> AVCaptureDevice.FlashMode {
        guard photoOutput.supportedFlashModes.contains(configuration.photo.flashMode) else {
            return .off
        }
        return configuration.photo.flashMode
    }

    private func emit(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        guard canAcceptFrames() else { return }
        guard !isPaused else { return }
        frameIndex += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        lastPresentationTime = presentationTime
        lastMediaType = mediaType.rawValue
        if mediaType == .video {
            lastVideoSampleBuffer = sampleBuffer
            lastVideoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        }
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
            self.frameHandler?(frame)
            self.delegate?.mediaSource(self, didOutput: frame)
            self.outputNode.transmit(frame) { _ in }
        }
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

    private func requestRequiredAuthorizations(completion: @escaping (Bool) -> Void) {
        let mediaTypes = configuration.requestedMediaTypes
        guard !mediaTypes.isEmpty else {
            completion(true)
            return
        }
        let lock = NSLock()
        var allGranted = true
        var remainingRequests = 0

        func finishIfNeeded() {
            lock.lock()
            let shouldComplete = remainingRequests == 0
            let granted = allGranted
            lock.unlock()
            if shouldComplete {
                completion(granted)
            }
        }

        for mediaType in mediaTypes {
            let status = Self.authorizationStatus(for: mediaType)
            if status == .authorized {
                continue
            }
            lock.lock()
            remainingRequests += 1
            lock.unlock()
            Self.requestAuthorization(for: mediaType) { status in
                lock.lock()
                if status != .authorized {
                    allGranted = false
                }
                if remainingRequests > 0 {
                    remainingRequests -= 1
                }
                lock.unlock()
                finishIfNeeded()
            }
        }
        finishIfNeeded()
    }

    private func notifyAuthorizationFailure() {
        let status = Self.authorizationStatus(for: configuration.captureMode)
        publish(.authorizationChanged(status))
        let error = CameraSourceError.authorizationDenied(requestedMediaTypes: configuration.requestedMediaTypes)
        DispatchQueue.main.async {
            self.delegate?.mediaSource(self, didFail: error)
        }
    }

    private func applyMirroring(for position: CameraPosition) {
        let mirrored = configuration.effectiveMirroringValue(for: position)
        if let previewConnection = previewLayer.connection, previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = mirrored
        }
        if let videoConnection = videoOutput.connection(with: .video), videoConnection.isVideoMirroringSupported {
            videoConnection.automaticallyAdjustsVideoMirroring = false
            videoConnection.isVideoMirrored = mirrored
        }
    }

    private func applyCurrentConnections() {
        if let previewConnection = previewLayer.connection, previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = currentOrientation
        }
        if let videoConnection = videoOutput.connection(with: .video) {
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = currentOrientation
            }
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .auto
            }
        }
        applyMirroring(for: currentPosition)
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

    private func startObservingNotifications() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: .AVCaptureSessionDidStartRunning,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.publish(.didStartRunning)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .AVCaptureSessionDidStopRunning,
                object: session,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.publish(.didStopRunning)
                DispatchQueue.main.async {
                    self.delegate?.mediaSourceDidFinish(self)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] notification in
                self?.handleRuntimeError(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .AVCaptureSessionWasInterrupted,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.publish(.wasInterrupted)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .AVCaptureSessionInterruptionEnded,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.publish(.interruptionEnded)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.updateCurrentOrientation()
            }
        )
    }

    private func stopObservingNotifications() {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func updateCurrentOrientation() {
        currentOrientation = Self.videoOrientation(from: UIDevice.current.orientation) ?? currentOrientation
        applyCurrentConnections()
    }

    private static func videoOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return nil
        }
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let isRecoverable = error?.domain == AVFoundationErrorDomain && error?.code == AVError.mediaServicesWereReset.rawValue
        publish(.runtimeError(isRecoverable: isRecoverable, description: error?.localizedDescription))
        if let error {
            DispatchQueue.main.async {
                self.delegate?.mediaSource(self, didFail: error)
            }
        }
        guard isRecoverable else { return }
        sessionQueue.async {
            guard !self.session.isRunning, self.authorizationStatus == .authorized else { return }
            self.session.startRunning()
        }
    }

    private static func attachmentsDictionary(from sampleBuffer: CMSampleBuffer?) -> [String: Any] {
        guard let sampleBuffer else { return [:] }
        let attachments = CMCopyDictionaryOfAttachments(
            allocator: kCFAllocatorDefault,
            target: sampleBuffer,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        ) as? [String: Any]
        return attachments ?? [:]
    }
}

extension CameraSource: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === videoOutput {
            emit(sampleBuffer: sampleBuffer, mediaType: .video)
        } else if output === audioOutput {
            emit(sampleBuffer: sampleBuffer, mediaType: .audio)
        }
    }
}

extension CameraSource: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.delegate?.mediaSource(self, didFail: error)
            }
            return
        }
        let result = CameraPhotoCaptureResult(
            data: photo.fileDataRepresentation(),
            metadata: photo.metadata,
            isFromCurrentFrame: false
        )
        DispatchQueue.main.async {
            self.photoCaptureHandler?(result)
        }
    }
}
#endif
