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
    case cannotAddMetadataOutput
    case cannotAddDepthOutput
    case photoFrameUnavailable
    case cannotCapturePhoto
    case unsupportedFeature(String)

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
        case .cannotAddMetadataOutput:
            return "Cannot add metadata output"
        case .cannotAddDepthOutput:
            return "Cannot add depth output"
        case .photoFrameUnavailable:
            return "No current frame is available for photo capture"
        case .cannotCapturePhoto:
            return "Photo output is unavailable for capture"
        case .unsupportedFeature(let description):
            return "Unsupported camera feature: \(description)"
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
        public let capabilitySnapshot: CameraCapabilitySnapshot
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
        public let capabilitySnapshot: CameraCapabilitySnapshot

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
            text += " · metadata \(capabilitySnapshot.supportsMetadataObjects.rawValue)"
            text += " · depth \(capabilitySnapshot.supportsDepthData.rawValue)"
            text += " · portrait \(capabilitySnapshot.supportsPortraitEffectsMatte.rawValue)"
            text += " · multicam \(capabilitySnapshot.supportsMultiCam.rawValue)"
            return text
        }
    }

    public enum MetadataKey {
        public static let mediaType = "kakapos.camera.media-type"
        public static let cameraPosition = "kakapos.camera.position"
        public static let sessionState = "kakapos.camera.session-state"
        public static let deviceOrientation = "kakapos.camera.device-orientation"
        public static let mirrored = "kakapos.camera.mirrored"
        public static let captureKind = "kakapos.camera.capture-kind"
        public static let depthDelivered = "kakapos.camera.depth-delivered"
        public static let portraitEffectsMatteDelivered = "kakapos.camera.portrait-matte-delivered"
    }

    public weak var delegate: MediaSourceDelegate?
    public let session: AVCaptureSession
    public let previewLayer: AVCaptureVideoPreviewLayer
    public let advancedOutput = CameraAdvancedOutput()
    public let audioSessionController = CameraAudioSessionController()
    public private(set) var deviceController: CameraDeviceController!
    public private(set) var isPaused: Bool = false
    public private(set) var state: CameraSessionState = .idle
    public private(set) var currentPosition: CameraPosition
    public private(set) var authorizationStatus: CameraAuthorizationStatus
    public private(set) var configuration: CameraSourceConfiguration
    public var frameHandler: ((MediaFrame) -> Void)?
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?
    public var photoCaptureHandler: ((CameraPhotoCaptureResult) -> Void)?
    public var authorizationStatusChangedHandler: ((CameraAuthorizationStatus) -> Void)?
    public var isRecordingActiveProvider: (() -> Bool)?

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
            lastMediaType: lastMediaType,
            capabilitySnapshot: capabilitySnapshot
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
            lastMediaType: currentSnapshot.lastMediaType,
            capabilitySnapshot: currentSnapshot.capabilitySnapshot
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
                "mediaType": currentSnapshot.lastMediaType ?? "n/a",
                "metadataSupport": currentSnapshot.capabilitySnapshot.supportsMetadataObjects.rawValue,
                "depthSupport": currentSnapshot.capabilitySnapshot.supportsDepthData.rawValue,
                "portraitSupport": currentSnapshot.capabilitySnapshot.supportsPortraitEffectsMatte.rawValue
            ]
        )
    }

    public var capabilitySnapshot: CameraCapabilitySnapshot {
        let device = videoInput?.device
        let depthSupport: CameraFeatureSupport
        if configuration.advanced.enablesDepthData {
            depthSupport = supportsDepthData(device: device) ? .supported : .unsupported
        } else {
            depthSupport = device == nil ? .unknown : .unsupported
        }
        let portraitSupport: CameraFeatureSupport
        if configuration.photo.deliversPortraitEffectsMatte || configuration.advanced.enablesPortraitEffectsMatte {
            portraitSupport = supportsPortraitEffectsMatte ? .supported : .unsupported
        } else {
            portraitSupport = device == nil ? .unknown : .unsupported
        }
        let metadataSupport: CameraFeatureSupport
        if configuration.advanced.metadataObjectTypes.isEmpty && configuration.capabilityDefaults.enablesMetadataObjectsWhenAvailable == false {
            metadataSupport = device == nil ? .unknown : .unsupported
        } else {
            metadataSupport = .supported
        }
        let dimensions: CGSize?
        if let formatDescription = device?.activeFormat.formatDescription {
            let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
            dimensions = CGSize(width: Int(dims.width), height: Int(dims.height))
        } else {
            dimensions = nil
        }
        return CameraCapabilitySnapshot(
            supportsAudioCapture: configuration.captureMode.includesAudio,
            supportsPhotoCapture: true,
            supportsMetadataObjects: metadataSupport,
            supportsDepthData: depthSupport,
            supportsPortraitEffectsMatte: portraitSupport,
            supportsARFrameSource: configuration.advanced.enablesARFrameSource ? .supported : .unsupported,
            supportsMultiCam: AVCaptureMultiCamSession.isMultiCamSupported ? .supported : .unsupported,
            supportsTorch: device?.hasTorch == true ? .supported : (device == nil ? .unknown : .unsupported),
            supportsFlash: device?.hasFlash == true ? .supported : (device == nil ? .unknown : .unsupported),
            currentPosition: currentPosition,
            isMirrored: configuration.effectiveMirroringValue(for: currentPosition),
            activeVideoDimensions: dimensions
        )
    }

    private let sessionQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.session")
    private let videoOutputQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.video")
    private let audioOutputQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.audio")
    private let processingQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.processing")
    private let photoQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.photo")
    private let outputNode = MediaOutputNode()
    private var lifecycle: CameraSessionLifecycle
    private var frameIndex: Int64 = 0
    private var lastPresentationTime: CMTime?
    private var lastMediaType: String?
    private var currentOrientation: AVCaptureVideoOrientation = .portrait
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true
    private let ownsSession: Bool

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var metadataOutput: AVCaptureMetadataOutput?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let ciContext = CIContext(options: nil)
    private var notificationObservers: [NSObjectProtocol] = []
    private var deviceObservers: [NSKeyValueObservation] = []
    private let sessionEventDispatcher = CameraEventDispatcher<CameraSessionEvent>()
    private let authorizationDispatcher = CameraEventDispatcher<CameraAuthorizationStatus>()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false
    private var lastVideoPixelBuffer: CVPixelBuffer?
    private var lastVideoSampleBuffer: CMSampleBuffer?
    private var shouldResumeAfterInterruption = false
    private var audioSessionEventToken: UUID?

    public init(configuration: CameraSourceConfiguration = CameraSourceConfiguration()) throws {
        let session = AVCaptureSession()
        self.session = session
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.configuration = configuration
        self.currentPosition = configuration.preferredPosition
        self.authorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.lifecycle = CameraSessionLifecycle(
            position: configuration.preferredPosition,
            authorizationStatus: Self.authorizationStatus(for: configuration.captureMode)
        )
        self.ownsSession = true
        super.init()
        configureDeviceController()
        configurePreviewLayer()
        applySessionPreset()
        updateCurrentOrientation()
        startObservingNotifications()
        wireAudioSessionEvents()
    }

    public init(session: AVCaptureSession, configuration: CameraSourceConfiguration) throws {
        self.session = session
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.configuration = configuration
        self.currentPosition = configuration.preferredPosition
        self.authorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.lifecycle = CameraSessionLifecycle(
            position: configuration.preferredPosition,
            authorizationStatus: Self.authorizationStatus(for: configuration.captureMode)
        )
        self.ownsSession = false
        super.init()
        configureDeviceController()
        configurePreviewLayer()
        applySessionPreset()
        updateCurrentOrientation()
        startObservingNotifications()
        wireAudioSessionEvents()
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
            if #available(iOS 11.0, *) {
                if self.photoOutput.isDepthDataDeliverySupported {
                    settings.isDepthDataDeliveryEnabled = self.configuration.photo.deliversDepthData || self.configuration.advanced.enablesDepthData
                    settings.embedsDepthDataInPhoto = settings.isDepthDataDeliveryEnabled
                }
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    settings.isPortraitEffectsMatteDeliveryEnabled = self.configuration.photo.deliversPortraitEffectsMatte || self.configuration.advanced.enablesPortraitEffectsMatte
                }
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

    @discardableResult
    public func addSessionEventObserver(_ handler: @escaping (CameraSessionEvent) -> Void) -> UUID {
        sessionEventDispatcher.addObserver(handler)
    }

    public func removeSessionEventObserver(_ token: UUID) {
        sessionEventDispatcher.removeObserver(token)
    }

    @discardableResult
    public func addAuthorizationObserver(_ handler: @escaping (CameraAuthorizationStatus) -> Void) -> UUID {
        authorizationDispatcher.addObserver(handler)
    }

    public func removeAuthorizationObserver(_ token: UUID) {
        authorizationDispatcher.removeObserver(token)
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

    func _handleSessionInterruptionForTesting(recordingActive: Bool) {
        handleSessionInterruption(isRecordingActive: recordingActive)
    }

    func _handleSessionInterruptionEndedForTesting() {
        handleSessionInterruptionEnded()
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

    private func configureDeviceController() {
        deviceController = CameraDeviceController(
            deviceProvider: { [weak self] in self?.videoInput?.device },
            positionProvider: { [weak self] in self?.currentPosition ?? .unspecified }
        )
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
        defer { session.commitConfiguration() }
        applySessionPreset()
        try configureVideoInput(position: configuration.preferredPosition)
        try configureAudioInputIfNeeded()
        try configureVideoOutput()
        try configureAudioOutputIfNeeded()
        try configurePhotoOutput()
        try configureMetadataOutputIfNeeded()
        try configureDepthOutputIfNeeded()
        applyCurrentConnections()
        applyInitialDeviceConfigurationIfNeeded()
        installDeviceObservers()
        isSessionConfigured = true
    }

    private func configureVideoInput(position: CameraPosition) throws {
        let resolvedPosition = position == .unspecified ? .back : position
        guard let device = findVideoDevice(position: resolvedPosition) else {
            throw CameraSourceError.captureDeviceUnavailable(position: resolvedPosition, preferredDeviceTypes: configuration.preferredDeviceTypes)
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
            try configureDepthOutputIfNeeded()
            applyCurrentConnections()
            applyInitialDeviceConfigurationIfNeeded()
            installDeviceObservers()
        } catch {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                videoInput = previousInput
                currentPosition = Self.cameraPosition(from: previousInput.device.position)
                applyCurrentConnections()
                installDeviceObservers()
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
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
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
        if #available(iOS 11.0, *) {
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = configuration.photo.deliversDepthData || configuration.advanced.enablesDepthData
            }
            if photoOutput.isPortraitEffectsMatteDeliverySupported {
                photoOutput.isPortraitEffectsMatteDeliveryEnabled = configuration.photo.deliversPortraitEffectsMatte || configuration.advanced.enablesPortraitEffectsMatte
            }
        }
    }

    private func configureMetadataOutputIfNeeded() throws {
        guard configuration.advanced.metadataObjectTypes.isEmpty == false else { return }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            throw CameraSourceError.cannotAddMetadataOutput
        }
        session.addOutput(output)
        let supported = configuration.advanced.metadataObjectTypes.filter(output.availableMetadataObjectTypes.contains)
        output.metadataObjectTypes = supported
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        metadataOutput = output
    }

    private func configureDepthOutputIfNeeded() throws {
        guard configuration.advanced.enablesDepthData else { return }
        guard #available(iOS 11.0, *) else {
            throw CameraSourceError.unsupportedFeature("depth data")
        }
        if let existing = depthDataOutput {
            session.removeOutput(existing)
            depthDataOutput = nil
        }
        let output = AVCaptureDepthDataOutput()
        output.setDelegate(self, callbackQueue: videoOutputQueue)
        guard session.canAddOutput(output) else {
            throw CameraSourceError.cannotAddDepthOutput
        }
        session.addOutput(output)
        depthDataOutput = output
        if let connection = output.connections.first, connection.isVideoOrientationSupported {
            connection.videoOrientation = currentOrientation
        }
        if configuration.advanced.requiresSynchronizedDepthData {
            let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, output])
            synchronizer.setDelegate(self, queue: videoOutputQueue)
            outputSynchronizer = synchronizer
        } else {
            outputSynchronizer = nil
        }
    }

    private func supportsDepthData(device: AVCaptureDevice?) -> Bool {
        guard let device else { return false }
        if #available(iOS 11.0, *) {
            return device.activeDepthDataFormat != nil || device.deviceType == .builtInTrueDepthCamera
        }
        return false
    }

    private var supportsPortraitEffectsMatte: Bool {
        if #available(iOS 12.0, *) {
            return photoOutput.isPortraitEffectsMatteDeliverySupported
        }
        return false
    }

    private func applyInitialDeviceConfigurationIfNeeded() {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            return
        }
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(configuration.device.focusMode.avFoundationMode) {
            device.focusMode = configuration.device.focusMode.avFoundationMode
        }
        if device.isExposureModeSupported(configuration.device.exposureMode.avFoundationMode) {
            device.exposureMode = configuration.device.exposureMode.avFoundationMode
        }
        if device.isWhiteBalanceModeSupported(configuration.device.whiteBalanceMode.avFoundationMode) {
            device.whiteBalanceMode = configuration.device.whiteBalanceMode.avFoundationMode
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = configuration.device.enablesSmoothAutoFocus
        }
        device.isSubjectAreaChangeMonitoringEnabled = configuration.device.subjectAreaMonitoringEnabled
        let zoomFactor = min(max(configuration.device.initialZoomFactor, 1), device.activeFormat.videoMaxZoomFactor)
        device.videoZoomFactor = zoomFactor
        if let range = configuration.video.preferredFrameRateRange {
            let minDuration = range.maximumFramesPerSecond > 0 ? CMTime(seconds: 1 / range.maximumFramesPerSecond, preferredTimescale: 600) : .invalid
            let maxDuration = range.minimumFramesPerSecond > 0 ? CMTime(seconds: 1 / range.minimumFramesPerSecond, preferredTimescale: 600) : .invalid
            if minDuration.isValid, maxDuration.isValid {
                device.activeVideoMinFrameDuration = minDuration
                device.activeVideoMaxFrameDuration = maxDuration
            }
        }
    }

    private func findVideoDevice(position: CameraPosition) -> AVCaptureDevice? {
        let requestedPosition = avDevicePosition(from: position)
        let preferredTypes = configuration.preferredDeviceTypes.flatMap(\.avFoundationTypes)
        let deviceTypes = preferredTypes.isEmpty ? [AVCaptureDevice.DeviceType.builtInWideAngleCamera] : preferredTypes
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: requestedPosition)
        if let device = discoverySession.devices.first {
            return device
        }
        if requestedPosition != .unspecified {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: requestedPosition)
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func resolvedFlashMode() -> AVCaptureDevice.FlashMode {
        let preferred = deviceController.preferredFlashMode
        guard photoOutput.supportedFlashModes.contains(preferred) else {
            return .off
        }
        return preferred
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
        var frame = SampleBufferFrame(
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
                    MetadataKey.mirrored: configuration.effectiveMirroringValue(for: currentPosition),
                    MetadataKey.captureKind: mediaType == .video ? "video" : "audio"
                ]
            )
        )
        frame.metadata.frameIndex = frameIndex
        DispatchQueue.main.async {
            self.frameHandler?(frame)
            self.delegate?.mediaSource(self, didOutput: frame)
        }
        processingQueue.async {
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
            self.sessionEventDispatcher.emit(event)
            if case .authorizationChanged(let status) = event {
                self.authorizationStatusChangedHandler?(status)
                self.authorizationDispatcher.emit(status)
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
                videoConnection.preferredVideoStabilizationMode = configuration.video.preferredStabilizationMode.avFoundationMode
            }
        }
        if let depthConnection = depthDataOutput?.connection(with: .depthData), depthConnection.isVideoOrientationSupported {
            depthConnection.videoOrientation = currentOrientation
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
            center.addObserver(forName: .AVCaptureSessionDidStartRunning, object: session, queue: nil) { [weak self] _ in
                self?.publish(.didStartRunning)
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionDidStopRunning, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.publish(.didStopRunning)
                DispatchQueue.main.async {
                    self.delegate?.mediaSourceDidFinish(self)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] notification in
                self?.handleRuntimeError(notification)
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
                self?.handleSessionInterruption(isRecordingActive: self?.isRecordingActiveProvider?() == true)
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
                self?.handleSessionInterruptionEnded()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                self?.updateCurrentOrientation()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: nil, queue: nil) { [weak self] _ in
                self?.deviceController.notifySubjectAreaChanged()
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureInputPortFormatDescriptionDidChange, object: nil, queue: nil) { [weak self] notification in
                guard let port = notification.object as? AVCaptureInput.Port else { return }
                guard let formatDescription = port.formatDescription else { return }
                self?.deviceController.notifyCleanApertureChanged(CMVideoFormatDescriptionGetCleanAperture(formatDescription, originIsAtTopLeft: true))
            }
        )
    }

    private func stopObservingNotifications() {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func wireAudioSessionEvents() {
        audioSessionEventToken = audioSessionController.addEventObserver { [weak self] event in
            self?.handleAudioSessionEvent(event)
        }
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

    private func handleSessionInterruption(isRecordingActive: Bool) {
        if !isPaused {
            isPaused = true
            shouldResumeAfterInterruption = true
        } else {
            shouldResumeAfterInterruption = false
        }
        publish(isRecordingActive ? .wasInterruptedWhileRecording : .wasInterrupted)
    }

    private func handleSessionInterruptionEnded() {
        if shouldResumeAfterInterruption {
            isPaused = false
            publish(.resumeRequested)
        }
        shouldResumeAfterInterruption = false
        publish(.interruptionEnded)
    }

    private func handleAudioSessionEvent(_ event: CameraAudioSessionController.Event) {
        switch event {
        case .routeChanged(let route):
            publish(.audioRouteChanged(route))
        case .didActivate, .didDeactivate, .activationFailed, .interruptionBegan, .interruptionEnded:
            break
        }
    }

    private func installDeviceObservers() {
        deviceObservers.removeAll()
        guard let device = videoInput?.device else { return }
        deviceObservers.append(
            device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.deviceController.emit(.focusAdjustmentChanged(value))
            }
        )
        deviceObservers.append(
            device.observe(\.isAdjustingExposure, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.deviceController.emit(.exposureAdjustmentChanged(value))
            }
        )
        deviceObservers.append(
            device.observe(\.lensPosition, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.deviceController.emit(.lensPositionChanged(value))
            }
        )
        deviceObservers.append(
            device.observe(\.exposureDuration, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.deviceController.emit(.exposureDurationChanged(value))
            }
        )
        deviceObservers.append(
            device.observe(\.iso, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.deviceController.emit(.isoChanged(value))
            }
        )
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
        if outputSynchronizer != nil, output === videoOutput {
            return
        }
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
        let deliveredDepthData: Bool
        let deliveredPortraitEffectsMatte: Bool
        if #available(iOS 11.0, *) {
            deliveredDepthData = photo.depthData != nil
        } else {
            deliveredDepthData = false
        }
        if #available(iOS 12.0, *) {
            deliveredPortraitEffectsMatte = photo.portraitEffectsMatte != nil
        } else {
            deliveredPortraitEffectsMatte = false
        }
        if deliveredDepthData, let lastPresentationTime {
            let payloadDepthData: AVDepthData?
            if #available(iOS 11.0, *) {
                payloadDepthData = photo.depthData
            } else {
                payloadDepthData = nil
            }
            advancedOutput.emitDepthData(.init(timestamp: lastPresentationTime, depthData: payloadDepthData, isSynchronized: false))
        }
        if deliveredPortraitEffectsMatte {
            let matte: AVPortraitEffectsMatte?
            if #available(iOS 12.0, *) {
                matte = photo.portraitEffectsMatte
            } else {
                matte = nil
            }
            advancedOutput.emitPortraitEffectsMatte(.init(deliveredInPhoto: true, matte: matte, timestamp: lastPresentationTime))
        }
        let result = CameraPhotoCaptureResult(
            data: photo.fileDataRepresentation(),
            metadata: photo.metadata,
            isFromCurrentFrame: false,
            depthDataDelivered: deliveredDepthData,
            portraitEffectsMatteDelivered: deliveredPortraitEffectsMatte
        )
        DispatchQueue.main.async {
            self.photoCaptureHandler?(result)
        }
    }
}

extension CameraSource: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let transformed = metadataObjects.compactMap { previewLayer.transformedMetadataObject(for: $0) }
        advancedOutput.emitMetadataObjects(.init(objects: metadataObjects, previewObjects: transformed, timestamp: lastPresentationTime))
    }
}

@available(iOS 11.0, *)
extension CameraSource: AVCaptureDepthDataOutputDelegate {
    public func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        advancedOutput.emitDepthData(.init(timestamp: timestamp, depthData: depthData, isSynchronized: false))
    }
}

@available(iOS 11.0, *)
extension CameraSource: AVCaptureDataOutputSynchronizerDelegate {
    public func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let synchronizedSampleBuffer = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }
        if synchronizedSampleBuffer.sampleBufferWasDropped == false {
            emit(sampleBuffer: synchronizedSampleBuffer.sampleBuffer, mediaType: .video)
        }
        if let depthDataOutput,
           let synchronizedDepth = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
           synchronizedDepth.depthDataWasDropped == false {
            advancedOutput.emitDepthData(.init(timestamp: synchronizedDepth.timestamp, depthData: synchronizedDepth.depthData, isSynchronized: true))
        }
    }
}
#endif
