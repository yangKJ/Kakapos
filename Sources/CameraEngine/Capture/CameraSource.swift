//
//  CameraSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
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

private final class WeakMediaSourceDelegateBox {
    weak var value: MediaSourceDelegate?
    let delivery: MediaSourceDelegateDelivery

    init(_ value: MediaSourceDelegate, delivery: MediaSourceDelegateDelivery = .main) {
        self.delivery = delivery
        self.value = value
    }
}

// 会话 mutation 在 sessionQueue，帧与 delegate 分支由 fence、准入 gate 和 delegateLock 约束。
// 跨队列只传递持有生命周期的回调载荷；调用者不得跨执行域直接修改配置。
public final class CameraSource: NSObject, MediaSource, MediaSourceDelegateMultiplexing, MediaFrameSourceNode, MediaSourceSnapshotProviding, @unchecked Sendable {
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
        public let frameIngressSnapshot: CameraFrameIngressSnapshot
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
        public let frameIngressSnapshot: CameraFrameIngressSnapshot
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
            text += " · ingress \(frameIngressSnapshot.inFlightFrameCount)/\(frameIngressSnapshot.maximumInFlightFrameCount)"
            text += " · dropped \(frameIngressSnapshot.droppedFrameCount)"
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

    public var delegate: MediaSourceDelegate? {
        get {
            delegateLock.lock()
            defer { delegateLock.unlock() }
            return primaryDelegate
        }
        set {
            delegateLock.lock()
            primaryDelegate = newValue
            delegateLock.unlock()
        }
    }
    public let session: AVCaptureSession
    public let previewLayer: AVCaptureVideoPreviewLayer
    public let advancedOutput = CameraAdvancedOutput()
    public private(set) var audioSessionController = CameraAudioSessionController()
    public private(set) var deviceController: CameraDeviceController!
    private var storedIsPaused: Bool = false
    public private(set) var isPaused: Bool {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedIsPaused }
        set { frameDeliveryFence.lock(); storedIsPaused = newValue; frameDeliveryFence.unlock() }
    }
    private var storedState: CameraSessionState = .idle
    public private(set) var state: CameraSessionState {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedState }
        set { frameDeliveryFence.lock(); storedState = newValue; frameDeliveryFence.unlock() }
    }
    private var storedCurrentPosition: CameraPosition
    public private(set) var currentPosition: CameraPosition {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedCurrentPosition }
        set { frameDeliveryFence.lock(); storedCurrentPosition = newValue; frameDeliveryFence.unlock() }
    }
    private var storedAuthorizationStatus: CameraAuthorizationStatus
    public private(set) var authorizationStatus: CameraAuthorizationStatus {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedAuthorizationStatus }
        set { frameDeliveryFence.lock(); storedAuthorizationStatus = newValue; frameDeliveryFence.unlock() }
    }
    public private(set) var configuration: CameraSourceConfiguration
    public var captureControlIdentity: String? {
        onSessionQueueSync {
            guard let device = videoInput?.device else { return nil }
            runLock.lock()
            defer { runLock.unlock() }
            guard let generation = runLifecycle.activeGeneration else { return nil }
            return device.uniqueID + ":" + String(generation) + ":" + String(controlConfigurationRevision)
        }
    }

    public var resolvedVideoSpecification: CameraVideoSpecification? {
        onSessionQueueSync {
            guard let device = videoInput?.device else { return nil }
            let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            func fps(_ duration: CMTime) -> Double? {
                let seconds = duration.seconds
                return seconds.isFinite && seconds > 0 ? 1 / seconds : nil
            }
            return CameraVideoSpecification(width: Int(size.width), height: Int(size.height),
                minimumFrameRate: fps(device.activeVideoMaxFrameDuration), maximumFrameRate: fps(device.activeVideoMinFrameDuration),
                pixelFormat: (videoOutput.videoSettings[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value,
                stabilizationMode: videoOutput.connection(with: .video).map { Int($0.activeVideoStabilizationMode.rawValue) },
                deviceIdentifier: device.uniqueID)
        }
    }

    private var storedFrameHandler: ((MediaFrame) -> Void)?
    public var frameHandler: ((MediaFrame) -> Void)? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedFrameHandler }
        set { frameDeliveryFence.lock(); storedFrameHandler = newValue; frameDeliveryFence.unlock() }
    }
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?
    private var storedPhotoCaptureHandler: ((CameraPhotoCaptureResult) -> Void)?
    public var photoCaptureHandler: ((CameraPhotoCaptureResult) -> Void)? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedPhotoCaptureHandler }
        set { frameDeliveryFence.lock(); storedPhotoCaptureHandler = newValue; frameDeliveryFence.unlock() }
    }
    public var authorizationStatusChangedHandler: ((CameraAuthorizationStatus) -> Void)?
    private var storedRecordingActiveProvider: (() -> Bool)?
    public var isRecordingActiveProvider: (() -> Bool)? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedRecordingActiveProvider }
        set { frameDeliveryFence.lock(); storedRecordingActiveProvider = newValue; frameDeliveryFence.unlock() }
    }

    private weak var primaryDelegate: MediaSourceDelegate?
    private let delegateLock = NSLock()
    private var additionalDelegates: [ObjectIdentifier: WeakMediaSourceDelegateBox] = [:]

    public var snapshot: Snapshot {
        frameDeliveryFence.lock()
        let values = (state, currentPosition, authorizationStatus, isPaused, currentOrientation, frameIndex, lastPresentationTime, lastMediaType)
        frameDeliveryFence.unlock()
        return Snapshot(
            state: values.0,
            position: values.1,
            authorizationStatus: values.2,
            isPaused: values.3,
            captureMode: configuration.captureMode,
            deviceOrientation: values.4,
            isMirrored: configuration.effectiveMirroringValue(for: currentPosition),
            lastFrameIndex: values.5 > 0 ? values.5 : nil,
            lastPresentationTime: values.6,
            lastMediaType: values.7,
            frameIngressSnapshot: frameIngressSnapshot,
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
            frameIngressSnapshot: currentSnapshot.frameIngressSnapshot,
            capabilitySnapshot: currentSnapshot.capabilitySnapshot
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public func addMediaSourceDelegate(_ delegate: MediaSourceDelegate) {
        addMediaSourceDelegate(delegate, delivery: .main)
    }

    public func addMediaSourceDelegate(_ delegate: MediaSourceDelegate, delivery: MediaSourceDelegateDelivery) {
        delegateLock.lock()
        additionalDelegates = additionalDelegates.filter { $0.value.value != nil }
        additionalDelegates[ObjectIdentifier(delegate)] = WeakMediaSourceDelegateBox(delegate, delivery: delivery)
        delegateLock.unlock()
    }

    public func removeMediaSourceDelegate(_ delegate: MediaSourceDelegate) {
        delegateLock.lock()
        additionalDelegates.removeValue(forKey: ObjectIdentifier(delegate))
        delegateLock.unlock()
    }

    var recorderConfiguration: RecorderSink.Configuration {
        let config = configuration
        return RecorderSink.Configuration(dimensions: config.video.dimensions, bitRate: config.video.bitRate,
            codec: config.video.codec, scalingMode: config.video.scalingMode, transform: config.video.transform,
            includesAudio: config.captureMode.includesAudio, audioBitRate: config.audio.bitRate,
            audioSampleRate: config.audio.sampleRate, audioChannelCount: config.audio.channelCount, colorPolicy: config.video.colorPolicy)
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
                "ingressInFlight": String(currentSnapshot.frameIngressSnapshot.inFlightFrameCount),
                "ingressMaximum": String(currentSnapshot.frameIngressSnapshot.maximumInFlightFrameCount),
                "ingressHighWater": String(currentSnapshot.frameIngressSnapshot.highWaterMark),
                "droppedVideoFrames": String(currentSnapshot.frameIngressSnapshot.droppedVideoFrameCount),
                "droppedAudioFrames": String(currentSnapshot.frameIngressSnapshot.droppedAudioFrameCount),
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

    public var frameIngressSnapshot: CameraFrameIngressSnapshot {
        frameIngressGate.snapshot
    }

    private let zoomRequestGate = CameraZoomRequestGate()
    private var zoomController: CameraZoomController?
    private var nativePreviewEnabled = true

    let sessionOwner: CameraSessionOwner
    private let sessionBranchID = UUID()
    private var sessionQueue: DispatchQueue { sessionOwner.queue }
    private let sessionQueueKey = DispatchSpecificKey<Void>()
    /// 视频与音频统一进入同一个 owner，保证 frameIndex 与最近帧元数据严格有序。
    private let mediaOutputQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.media-output")
    private let processingQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.processing")
    private let photoQueue = DispatchQueue(label: "com.condy.kakapos.camera-source.photo")
    private let outputNode = MediaOutputNode()
    private let frameIngressGate: CameraFrameIngressGate
    private let runLock = NSLock()
    private let frameDeliveryFence = NSRecursiveLock()
    private let observerIngressGate = CameraFrameIngressGate(maximumInFlightFrameCount: 6)
    private var runLifecycle = CameraRunLifecycle()
    private var lifecycle: CameraSessionLifecycle
    private var storedFrameIndex: Int64 = 0
    private var frameIndex: Int64 {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedFrameIndex }
        set { frameDeliveryFence.lock(); storedFrameIndex = newValue; frameDeliveryFence.unlock() }
    }
    private var storedLastPresentationTime: CMTime?
    private var lastPresentationTime: CMTime? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedLastPresentationTime }
        set { frameDeliveryFence.lock(); storedLastPresentationTime = newValue; frameDeliveryFence.unlock() }
    }
    private var storedLastMediaType: String?
    private var lastMediaType: String? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedLastMediaType }
        set { frameDeliveryFence.lock(); storedLastMediaType = newValue; frameDeliveryFence.unlock() }
    }
    private var storedCurrentOrientation: AVCaptureVideoOrientation = .portrait
    private var currentOrientation: AVCaptureVideoOrientation {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedCurrentOrientation }
        set { frameDeliveryFence.lock(); storedCurrentOrientation = newValue; frameDeliveryFence.unlock() }
    }
    private let ownsSession: Bool
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var photoOutput = AVCapturePhotoOutput()
    private var configurationTransaction: CameraCaptureTransaction?
    private var ownsRunAudioLease = false
    private final class PhotoDelivery: @unchecked Sendable {
        let handler: ((CameraPhotoCaptureResult) -> Void)?
        let delegates: [MediaSourceDelegate]
        let result = CameraPhotoRequestResult<CameraPhotoCaptureResult>()
        init(handler: ((CameraPhotoCaptureResult) -> Void)?, delegates: [MediaSourceDelegate]) { self.handler = handler; self.delegates = delegates }
    }
    private let photoDeliveryLock = NSLock()
    private var photoDeliveries: [Int64: PhotoDelivery] = [:]
    private func takePhotoDelivery(_ id: Int64) -> PhotoDelivery? {
        photoDeliveryLock.lock(); defer { photoDeliveryLock.unlock() }
        return photoDeliveries.removeValue(forKey: id)
    }
    private func photoDelivery(_ id: Int64) -> PhotoDelivery? {
        photoDeliveryLock.lock(); defer { photoDeliveryLock.unlock() }
        return photoDeliveries[id]
    }
    private func finishPhoto(_ delivery: PhotoDelivery, error: Error? = nil) {
        guard let result = delivery.result.finish(error: error) else { return }
        let transfer = CameraCallbackTransfer(result)
        DispatchQueue.main.async {
            switch transfer.value {
            case .success(let photo): delivery.handler?(photo)
            case .failure(let error): delivery.delegates.forEach { $0.mediaSource(self, didFail: error) }
            }
        }
    }
    private func failPhoto(_ delivery: PhotoDelivery, error: Error) { finishPhoto(delivery, error: error) }
    private func completePhotoDelivery(_ id: Int64, error: Error?) {
        guard let delivery = takePhotoDelivery(id) else { return }
        finishPhoto(delivery, error: error)
    }
    private var nativePhotoRequests: [Int64: NativePhotoRequestDelegate] = [:]
    private var storedMetadataOutput: AVCaptureMetadataOutput?
    private var metadataOutput: AVCaptureMetadataOutput? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedMetadataOutput }
        set { frameDeliveryFence.lock(); storedMetadataOutput = newValue; frameDeliveryFence.unlock() }
    }
    private var storedDepthDataOutput: AVCaptureDepthDataOutput?
    private var depthDataOutput: AVCaptureDepthDataOutput? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedDepthDataOutput }
        set { frameDeliveryFence.lock(); storedDepthDataOutput = newValue; frameDeliveryFence.unlock() }
    }
    private var storedOutputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedOutputSynchronizer }
        set { frameDeliveryFence.lock(); storedOutputSynchronizer = newValue; frameDeliveryFence.unlock() }
    }
    private let ciContext = CIContext(options: nil)
    private var notificationObservers: [NSObjectProtocol] = []
    private var deviceObservers: [NSKeyValueObservation] = []
    private let sessionEventDispatcher = CameraEventDispatcher<CameraSessionEvent>()
    private let authorizationDispatcher = CameraEventDispatcher<CameraAuthorizationStatus>()
    private var storedVideoInput: AVCaptureDeviceInput?
    private var videoInput: AVCaptureDeviceInput? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedVideoInput }
        set { frameDeliveryFence.lock(); storedVideoInput = newValue; frameDeliveryFence.unlock() }
    }
    private var storedAudioInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput? {
        get { frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }; return storedAudioInput }
        set { frameDeliveryFence.lock(); storedAudioInput = newValue; frameDeliveryFence.unlock() }
    }
    private var isSessionConfigured = false
    // 会话队列持有；同一设备在媒体服务恢复后也必须重放硬件意图。
    private var controlConfigurationRevision: UInt64 = 0
    private let hardwareObservationLock = NSLock()
    private var cachedHardwareObservation: CameraHardwareObservation?
    private var hardwareObservationRequestedAt: Double = 0
    private var hardwareObservationEpoch = UUID()
    private let lastVideoFrameLock = NSLock()
    private var lastVideoSampleBuffer: CMSampleBuffer?
    private var framesAreReady = false
    private var earliestFrameTime: CMTime?
    private var shouldResumeAfterInterruption = false
    private var audioSessionEventToken: UUID?

    public init(configuration: CameraSourceConfiguration = CameraSourceConfiguration()) throws {
        let session = AVCaptureSession()
        self.session = session
        let owner = CameraSessionOwner.shared(for: session)
        self.sessionOwner = owner
        self.previewLayer = owner.sync {
            if #available(iOS 13.0, *), session is AVCaptureMultiCamSession {
                return AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            }
            return AVCaptureVideoPreviewLayer(session: session)
        }
        self.configuration = configuration
        self.storedCurrentPosition = configuration.preferredPosition
        self.storedAuthorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.frameIngressGate = CameraFrameIngressGate(
            maximumInFlightFrameCount: configuration.maximumInFlightFrameCount
        )
        self.lifecycle = CameraSessionLifecycle(
            position: configuration.preferredPosition,
            authorizationStatus: Self.authorizationStatus(for: configuration.captureMode)
        )
        self.ownsSession = true
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
        configureDeviceController()
        deviceController.sessionOwner = sessionOwner
        configurePreviewLayer()
        sessionOwner.sync {
            applySessionPreset()
            updateCurrentOrientation()
        }
        startObservingNotifications()
        wireAudioSessionEvents()
    }

    public init(session: AVCaptureSession, configuration: CameraSourceConfiguration) throws {
        self.session = session
        let owner = CameraSessionOwner.shared(for: session)
        self.sessionOwner = owner
        self.previewLayer = owner.sync {
            if #available(iOS 13.0, *), session is AVCaptureMultiCamSession {
                return AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            }
            return AVCaptureVideoPreviewLayer(session: session)
        }
        self.configuration = configuration
        self.storedCurrentPosition = configuration.preferredPosition
        self.storedAuthorizationStatus = Self.authorizationStatus(for: configuration.captureMode)
        self.frameIngressGate = CameraFrameIngressGate(
            maximumInFlightFrameCount: configuration.maximumInFlightFrameCount
        )
        self.lifecycle = CameraSessionLifecycle(
            position: configuration.preferredPosition,
            authorizationStatus: Self.authorizationStatus(for: configuration.captureMode)
        )
        self.ownsSession = false
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
        configureDeviceController()
        deviceController.sessionOwner = sessionOwner
        configurePreviewLayer()
        sessionOwner.sync {
            applySessionPreset()
            updateCurrentOrientation()
        }
        startObservingNotifications()
        wireAudioSessionEvents()
    }

    deinit {
        stopObservingNotifications()
        sessionQueue.setSpecific(key: sessionQueueKey, value: nil)
        let owner = sessionOwner; let branch = sessionBranchID; let session = self.session
        let outputs: [AVCaptureOutput] = [videoOutput, audioOutput, photoOutput] + ([metadataOutput, depthDataOutput] as [AVCaptureOutput?]).compactMap { $0 }
        let inputs = [videoInput, audioInput].compactMap { $0 }
        let layer = previewLayer
        let preview = layer.connection
        let audio = audioSessionController; let releasesAudio = ownsRunAudioLease
        owner.queue.async {
            // 预览层必须活到会话拆除结束，避免其在主线程析构时与会话配置互相等锁。
            withExtendedLifetime(layer) {
                session.beginConfiguration()
                if let preview, session.connections.contains(where: { $0 === preview }) { session.removeConnection(preview) }
                for output in outputs where session.outputs.contains(where: { $0 === output }) { session.removeOutput(output) }
                for input in inputs where session.inputs.contains(where: { $0 === input }) { session.removeInput(input) }
                session.commitConfiguration()
                layer.session = nil
                owner.stop(branch)
                if releasesAudio { audio.deactivate() }
            }
        }
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
        onSessionQueue { [weak self] in
            self?.startOnSessionQueue()
        }
    }

    private func startOnSessionQueue() {
        guard !deferStartUntilTerminalHandoffIfNeeded() else { return }
        let status = Self.authorizationStatus(for: configuration.captureMode)
        authorizationStatus = status
        publish(.authorizationChanged(status))
        guard status == .authorized else {
            guard configuration.automaticallyRequestsAuthorization, status == .notDetermined else {
                let failureGeneration = invalidateRunForFailure()
                notifyAuthorizationFailure(generation: failureGeneration)
                return
            }
            guard let authorizationGeneration = beginAuthorizationRequestIfNeeded() else { return }
            requestRequiredAuthorizations { [weak self] granted in
                guard let self else { return }
                self.onSessionQueue {
                    guard self.completeAuthorizationRequest(generation: authorizationGeneration) else { return }
                    if granted {
                        self.startOnSessionQueue()
                    } else {
                        let failureGeneration = self.invalidateRunForFailure()
                            self.notifyAuthorizationFailure(generation: failureGeneration)
                    }
                }
            }
            return
        }
        guard let runGeneration = beginRunIfNeeded() else { return }
        refreshRuntimeStateForStart()
        publish(.startRequested)
        do {
            try acquireRunAudioLease()
            try ensureSessionConfigured()
            guard isActiveRunGeneration(runGeneration) else { return }
            applyCurrentConnections()
            setCaptureConnectionsEnabled(true)
            let wasAlreadyRunning = session.isRunning
            guard startSessionIfRunIsActive(generation: runGeneration) else { return }
            if wasAlreadyRunning {
                publishReady()
            }
        } catch {
            guard isActiveRunGeneration(runGeneration) else { return }
            let failureGeneration = invalidateRunForFailure()
            releaseRunAudioLease()
            publish(.runtimeError(isRecoverable: false, description: error.localizedDescription))
            DispatchQueue.main.async {
                guard self.frameIngressGate.isCurrentGeneration(failureGeneration) else { return }
                self.notifyDelegatesOfFailure(error)
            }
        }
    }

    /// 在原会话队列异步更新帧率，调用方不等待启动或停止；旧运行的请求直接取消。
    public func updateFrameRateRange(_ range: CameraFrameRateRange) async throws -> CameraDeviceSnapshot {
        try Task.checkCancellation()
        guard let generation = currentActiveRunGeneration() else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.isActiveRunGeneration(generation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let current = self.deviceController.snapshot
                    if current.activeFrameRateRange == range {
                        continuation.resume(returning: current)
                    } else {
                        continuation.resume(returning: try self.deviceController.selectFrameRateRange(range))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public var discardedZoomRequestCount: Int { zoomRequestGate.discardedCount }

    /// 异步变焦请求在会话串行域执行，排队期间被新请求替代时返回取消。
    public func updateZoomFactor(_ factor: CGFloat, rampRate: Float? = nil) async throws -> CameraDeviceSnapshot {
        guard factor.isFinite, factor >= 1 else { throw CameraDeviceControlError.invalidZoomFactor(factor) }
        guard let revision = zoomRequestGate.issue() else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.zoomRequestGate.accepts(revision) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do { continuation.resume(returning: try self.resolvedZoomController().update(factor, rampRate: rampRate)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// 关闭时先拒绝旧请求，再在同一队列内停止并冻结实际倍率。
    public func setZoomInteractionEnabled(_ enabled: Bool) async throws -> CameraDeviceSnapshot {
        let revision = zoomRequestGate.setEnabled(enabled)
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.zoomRequestGate.accepts(revision, requiresEnabled: false) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let controller = self.resolvedZoomController()
                controller.observe()
                controller.setSystemInteractionEnabled(enabled)
                if enabled {
                    guard self.videoInput != nil else {
                        continuation.resume(throwing: CameraDeviceControlError.deviceUnavailable)
                        return
                    }
                    controller.publish(system: false, force: true)
                    continuation.resume(returning: self.deviceController.snapshot)
                } else {
                    do { continuation.resume(returning: try controller.freeze()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    public func observeAppliedZoom(_ handler: @escaping @Sendable (_ factor: CGFloat, _ isSystemControl: Bool, _ isFinal: Bool) -> Void) {
        sessionQueue.async {
            let controller = self.resolvedZoomController()
            controller.onApplied = handler
            controller.observe()
            controller.publish(system: false, force: true)
        }
    }

    /// range 为 nil 时撤下本源创建的控件，既有消费者默认没有系统调焦控件。
    public func configureSystemZoomControl(range: ClosedRange<CGFloat>?, title: String = "Zoom") {
        sessionQueue.async { self.resolvedZoomController().configureSystemControl(range: range, title: title) }
    }

    /// 只控制视频流，图层和连接继续用于坐标换算。默认开启。
    public func setNativePreviewEnabled(_ enabled: Bool) {
        sessionQueue.async {
            self.nativePreviewEnabled = enabled
            self.previewLayer.connection?.isEnabled = enabled
        }
    }

    private func resolvedZoomController() -> CameraZoomController {
        if let zoomController { return zoomController }
        let controller = CameraZoomController(
            queue: sessionQueue,
            session: session,
            device: { [weak self] in self?.videoInput?.device },
            controls: deviceController,
            gate: zoomRequestGate
        )
        zoomController = controller
        return controller
    }

    public func pause() {
        isPaused = true
        onSessionQueue { self.publish(.pauseRequested) }
    }

    public func resume() {
        onSessionQueue {
            if self.currentActiveRunGeneration() != nil { self.setFramesReady(true, minimumTime: self.streamClockTime()) }
            self.isPaused = false
            self.publish(.resumeRequested)
        }
    }

    public func stop() {
        _ = zoomRequestGate.setEnabled(false)
        guard let terminalGeneration = beginTerminalIfNeeded() else { return }
        let terminalDelegates = CameraCallbackTransfer(mediaSourceDelegatesSnapshot())
        sessionQueue.async {
            self.zoomController?.invalidate()
            self.setCaptureConnectionsEnabled(false)
            self.setLastVideoSampleBuffer(nil)
            self.sessionOwner.stop(self.sessionBranchID) {
                self.expectStopNotification(generation: terminalGeneration)
            }
            self.releaseRunAudioLease()
            self.publish(.didStopRunning)
            DispatchQueue.main.async {
                self.notifyDelegatesOfFinish(terminalDelegates.value)
                self.markTerminalCallbackDelivered()
            }
        }
    }

    public func cancel() {
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
        _ = zoomRequestGate.setEnabled(false)
        let generation = frameIngressGate.currentGeneration
        sessionQueue.async { self.switchPositionOnSessionQueue(to: position, generation: generation) }
        return true
    }

    private func switchPositionOnSessionQueue(to position: CameraPosition, generation: UInt64) {
        guard frameIngressGate.isCurrentGeneration(generation) else { return }
        publish(.positionSwitchRequested(position))
        zoomController?.invalidate()
        if !isSessionConfigured {
            // 未建图时只保留镜头意图，避免建立半套输入后让首次启动重复添加。
            publish(.positionChanged(position))
            return
        }
        do {
            try replaceVideoInput(position: position)
            guard frameIngressGate.isCurrentGeneration(generation) else { return }
            applyMirroring(for: position)
            setCaptureConnectionsEnabled(currentActiveRunGeneration() != nil)
            publish(.positionChanged(position))
        } catch {
            guard frameIngressGate.isCurrentGeneration(generation) else { return }
            if let device = videoInput?.device, isSessionConfigured {
                let restored = Self.cameraPosition(from: device.position)
                setCaptureConnectionsEnabled(currentActiveRunGeneration() != nil)
                publish(.runtimeError(isRecoverable: true, description: error.localizedDescription))
                publish(.positionChanged(restored))
            } else if currentActiveRunGeneration() != nil { finishRuntimeFailure(error) }
            else { publish(.runtimeError(isRecoverable: false, description: error.localizedDescription)) }
        }
    }

    public func capturePhoto() {
        if configuration.captureMode != .photo { capturePhotoFromCurrentFrame(); return }
        let delivery = PhotoDelivery(handler: photoCaptureHandler, delegates: mediaSourceDelegatesSnapshot())
        let generation = currentActiveRunGeneration()
        sessionQueue.async {
            guard let generation, self.isActiveRunGeneration(generation), self.session.isRunning else {
                self.failPhoto(delivery, error: CameraPhotoCaptureError.sessionUnavailable); return
            }
            guard self.isSessionConfigured, self.session.isRunning else {
                self.capturePhotoFromCurrentFrame()
                return
            }
            guard self.photoOutput.connections.isEmpty == false else {
                self.failPhoto(delivery, error: CameraSourceError.cannotCapturePhoto)
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
            let id = settings.uniqueID
            self.photoDeliveryLock.lock(); self.photoDeliveries[id] = delivery; self.photoDeliveryLock.unlock()
            self.sessionQueue.asyncAfter(deadline: .now() + 45) { [weak self] in
                guard let self, let pending = self.takePhotoDelivery(id) else { return }
                self.failPhoto(pending, error: CameraPhotoCaptureError.captureTimedOut)
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// 只查询已配置输出的能力，不以硬件型号猜测支持范围。
    public func photoCaptureCapabilities() async -> CameraPhotoCaptureCapabilities {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                let device = self.videoInput?.device
                let dimensions: [CGSize]
                if #available(iOS 16.0, *) {
                    dimensions = device?.activeFormat.supportedMaxPhotoDimensions.map {
                        CGSize(width: Int($0.width), height: Int($0.height))
                    } ?? []
                } else { dimensions = [] }
                let proRaw: Bool
                if #available(iOS 14.3, *) { proRaw = self.photoOutput.isAppleProRAWSupported }
                else { proRaw = false }
                continuation.resume(returning: CameraPhotoCaptureCapabilities(
                    supportsLivePhoto: self.photoOutput.isLivePhotoCaptureSupported,
                    supportsBayerRAW: self.photoOutput.availableRawPhotoPixelFormatTypes.contains {
                        if #available(iOS 14.3, *) { return AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
                        return !proRaw
                    }, supportsAppleProRAW: proRaw, supportedDimensions: dimensions,
                    supportsHEIC: self.photoOutput.availablePhotoCodecTypes.contains(.hevc),
                    supportsUncompressedProcessed: self.photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA)))
            }
        }
    }

    /// 新请求路径没有当前视频帧回退；高质量捕获失败必须显式返回。
    public func capturePhoto(request: CameraPhotoCaptureRequest) async throws -> CameraPhotoCaptureArtifact {
        let task = CameraPhotoTask<CameraPhotoCaptureArtifact>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard task.begin(continuation) else { return }
                sessionQueue.async {
                    guard !task.isCancelled else { return }
                    do {
                        guard self.currentActiveRunGeneration() != nil, self.isSessionConfigured, self.session.isRunning,
                              self.photoOutput.connections.contains(where: { $0.isEnabled }) else { throw CameraPhotoCaptureError.sessionUnavailable }
                        guard self.nativePhotoRequests.count < 2 else { throw CameraPhotoCaptureError.tooManyRequests }
                        let expectsRaw = request.format == .bayerRAW || request.format == .appleProRAW
                        guard !(expectsRaw && request.includesLivePhoto) else { throw CameraPhotoCaptureError.incompatibleCombination }
                        if request.format == .appleProRAW {
                            if #available(iOS 14.3, *), self.photoOutput.isAppleProRAWSupported {
                                self.photoOutput.isAppleProRAWEnabled = true
                            } else { throw CameraPhotoCaptureError.unsupportedFormat }
                        }
                        let codec: AVVideoCodecType = request.format == .heic ? .hevc : .jpeg
                        if request.format != .uncompressedProcessed {
                            guard self.photoOutput.availablePhotoCodecTypes.contains(codec) else { throw CameraPhotoCaptureError.unsupportedFormat }
                        }
                        let settings: AVCapturePhotoSettings
                        if expectsRaw {
                            guard let rawType = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                                if #available(iOS 14.3, *) {
                                    return request.format == .appleProRAW ? AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) : AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
                                }
                                return request.format == .bayerRAW
                            }) else { throw CameraPhotoCaptureError.unsupportedFormat }
                            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: [AVVideoCodecKey: codec])
                        } else if request.format == .uncompressedProcessed {
                            guard !request.includesLivePhoto,
                                  self.photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
                                throw CameraPhotoCaptureError.unsupportedFormat
                            }
                            settings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                        } else { settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]) }
                        if #available(iOS 16.0, *) {
                            let supported = self.videoInput?.device.activeFormat.supportedMaxPhotoDimensions.sorted {
                                Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
                            } ?? []
                            guard let maximum = supported.last, let standard = supported.first else {
                                if request.maximumDimensions { throw CameraPhotoCaptureError.unsupportedFormat }
                                throw CameraPhotoCaptureError.sessionUnavailable
                            }
                            if self.photoOutput.maxPhotoDimensions.width != maximum.width || self.photoOutput.maxPhotoDimensions.height != maximum.height { self.photoOutput.maxPhotoDimensions = maximum }
                            settings.maxPhotoDimensions = request.maximumDimensions ? maximum : standard
                        }
                        guard request.flashMode == .off || self.photoOutput.supportedFlashModes.contains(request.flashMode) else {
                            throw CameraPhotoCaptureError.incompatibleCombination
                        }
                        settings.flashMode = request.flashMode
                        if #available(iOS 18.0, *), request.suppressesShutterSound, self.photoOutput.isShutterSoundSuppressionSupported {
                            settings.isShutterSoundSuppressionEnabled = true
                        }
                        if #available(iOS 13.0, *) { settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization }
                        if request.includesLivePhoto {
                            guard self.photoOutput.isLivePhotoCaptureSupported else { throw CameraPhotoCaptureError.livePhotoUnavailable }
                            self.photoOutput.isLivePhotoCaptureEnabled = true
                            guard !self.photoOutput.isLivePhotoCaptureSuspended else { throw CameraPhotoCaptureError.livePhotoUnavailable }
                            try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
                            settings.livePhotoMovieFileURL = request.resourceURL(task.resourceID, suffix: ".mov")
                        }
                        let uniqueID = settings.uniqueID
                        guard let delegate = self.registerNativePhotoRequest(request, uniqueID: uniqueID, task: task) else { return }
                        // 原生照片输出独立于预览连接；界面锁定方向时仍按当前握持方向保存。
                        if let connection = self.photoOutput.connection(with: .video) {
                            if connection.isVideoOrientationSupported {
                                connection.videoOrientation = request.videoOrientation ?? self.currentOrientation
                            }
                            if connection.isVideoMirroringSupported {
                                connection.automaticallyAdjustsVideoMirroring = false
                                connection.isVideoMirrored = false
                            }
                        }
                        self.photoOutput.capturePhoto(with: settings, delegate: delegate)
                    } catch { task.finish(.failure(error)) }
                }
            }
        } onCancel: { task.cancel() }
    }

    private func registerNativePhotoRequest(
        _ request: CameraPhotoCaptureRequest,
        uniqueID: Int64,
        task: CameraPhotoTask<CameraPhotoCaptureArtifact>
    ) -> NativePhotoRequestDelegate? {
        let delegate = NativePhotoRequestDelegate(request: request,
            hardwareObservation: deviceController.hardwareObservation(at: .photoRequest), resourceID: task.resourceID) { result in
            self.sessionQueue.async { self.nativePhotoRequests.removeValue(forKey: uniqueID) }
            if !task.finish(result.mapError { $0 as Error }), task.isCancelled, case .success(let artifact) = result {
                NativePhotoRequestDelegate.discard(artifact, request: request, resourceID: task.resourceID)
            }
        }
        task.onCancel { [weak self, weak delegate] in
            self?.sessionQueue.async {
                if self?.nativePhotoRequests[uniqueID] === delegate { self?.nativePhotoRequests.removeValue(forKey: uniqueID) }
                delegate?.cancel()
            }
        }
        guard !task.isCancelled else { delegate.cancel(); return nil }
        nativePhotoRequests[uniqueID] = delegate
        sessionQueue.asyncAfter(deadline: .now() + 45) { [weak delegate] in delegate?.terminate(.captureTimedOut) }
        return delegate
    }

    private func previewHardwareObservation() -> CameraHardwareObservation? {
        let now = ProcessInfo.processInfo.systemUptime
        hardwareObservationLock.lock()
        let cached = cachedHardwareObservation.flatMap { now - $0.hostTimeSeconds <= 1 ? $0 : nil }
        let shouldRequest = now - hardwareObservationRequestedAt >= 0.25
        let epoch = hardwareObservationEpoch
        if shouldRequest { hardwareObservationRequestedAt = now }
        hardwareObservationLock.unlock()
        if shouldRequest {
            sessionQueue.async {
                let observation = self.deviceController.hardwareObservation(at: .preview)
                self.hardwareObservationLock.lock()
                if self.hardwareObservationEpoch == epoch { self.cachedHardwareObservation = observation }
                self.hardwareObservationLock.unlock()
            }
        }
        return cached
    }

    private func setLastVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer?) {
        if sampleBuffer == nil {
            hardwareObservationLock.lock()
            cachedHardwareObservation = nil
            hardwareObservationRequestedAt = 0
            hardwareObservationEpoch = UUID()
            hardwareObservationLock.unlock()
        }
        lastVideoFrameLock.lock()
        lastVideoSampleBuffer = sampleBuffer
        lastVideoFrameLock.unlock()
    }

    private func lastVideoFrameSnapshot() -> CMSampleBuffer? {
        lastVideoFrameLock.lock()
        defer { lastVideoFrameLock.unlock() }
        return lastVideoSampleBuffer
    }

    private final class FramePhotoRequest: @unchecked Sendable {
        let sample: CMSampleBuffer
        let handler: ((CameraPhotoCaptureResult) -> Void)?
        let delegates: [MediaSourceDelegate]
        init(sample: CMSampleBuffer, handler: ((CameraPhotoCaptureResult) -> Void)?, delegates: [MediaSourceDelegate]) {
            self.sample = sample; self.handler = handler; self.delegates = delegates
        }
    }
    public func capturePhotoFromCurrentFrame() {
        frameDeliveryFence.lock()
        let sample = framesAreReady && currentActiveRunGeneration() != nil ? lastVideoFrameSnapshot() : nil
        let handler = photoCaptureHandler
        let delegates = mediaSourceDelegatesSnapshot()
        frameDeliveryFence.unlock()
        guard let sample else {
            let delivery = CameraCallbackTransfer(delegates)
            DispatchQueue.main.async { delivery.value.forEach { $0.mediaSource(self, didFail: CameraSourceError.photoFrameUnavailable) } }
            return
        }
        let request = FramePhotoRequest(sample: sample, handler: handler, delegates: delegates)
        photoQueue.async { self.produceFramePhoto(request) }
    }
    private func produceFramePhoto(_ request: FramePhotoRequest) {
        do {
            guard let buffer = CMSampleBufferGetImageBuffer(request.sample),
                  let data = ciContext.jpegRepresentation(of: CIImage(cvPixelBuffer: buffer), colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                throw CameraSourceError.photoFrameUnavailable
            }
            let resource = try CameraPhotoCaptureResource(encodedData: data, metadata: Self.attachmentsDictionary(from: request.sample),
                origin: .videoFrame, photoTimestampSeconds: CMSampleBufferGetPresentationTimeStamp(request.sample).seconds)
            let result = CameraCallbackTransfer(CameraPhotoCaptureResult(resource: resource))
            DispatchQueue.main.async { request.handler?(result.value) }
        } catch {
            let failure = CameraCallbackTransfer(error)
            DispatchQueue.main.async { request.delegates.forEach { $0.mediaSource(self, didFail: failure.value) } }
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
        if state == .running {
            lifecycle.handle(.didStartRunning)
            _ = beginRunIfNeeded()
            setFramesReady(true, minimumTime: nil)
        }
    }

    /// 合成流不监听模拟器空捕获会话的硬件通知；原生通知合同由独立用例验证。
    func _detachNativeNotificationsForTesting() {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
    }

    var _observerIngressSnapshotForTesting: CameraFrameIngressSnapshot { observerIngressGate.snapshot }

    func _queuePositionSwitchForTesting(_ position: CameraPosition) {
        let generation = frameIngressGate.currentGeneration
        sessionQueue.async { self.switchPositionOnSessionQueue(to: position, generation: generation) }
    }
    var _nativePhotoRequestCountForTesting: Int { onSessionQueueSync { nativePhotoRequests.count } }
    func _registerPhotoTaskForTesting(_ request: CameraPhotoCaptureRequest, uniqueID: Int64,
        task: CameraPhotoTask<CameraPhotoCaptureArtifact>) -> NativePhotoRequestDelegate? {
        onSessionQueueSync { registerNativePhotoRequest(request, uniqueID: uniqueID, task: task) }
    }
    func _beginLegacyPhotoForTesting(_ id: Int64) {
        let delivery = PhotoDelivery(handler: photoCaptureHandler, delegates: mediaSourceDelegatesSnapshot())
        photoDeliveryLock.lock(); photoDeliveries[id] = delivery; photoDeliveryLock.unlock()
    }
    func _stageLegacyPhotoForTesting(_ id: Int64, result: Result<CameraPhotoCaptureResult, Error>) {
        photoDelivery(id)?.result.stage(result)
    }
    func _finishLegacyPhotoForTesting(_ id: Int64, error: Error? = nil) { completePhotoDelivery(id, error: error) }

    func _setFrameTimeFenceForTesting(_ time: CMTime?) { setFramesReady(true, minimumTime: time) }
    func _configureTransactionForTesting(_ body: (AVCaptureSession) throws -> Void) throws {
        try onSessionQueueSync { try configureTransaction { try body(session) } }
    }
    func _useAudioSessionControllerForTesting(_ controller: CameraAudioSessionController) {
        onSessionQueueSync { audioSessionController = controller; wireAudioSessionEvents() }
    }
    func _acquireRunAudioForTesting() throws { try onSessionQueueSync { try acquireRunAudioLease() } }
    func _drainSessionQueueForTesting() {
        onSessionQueueSync {}
    }

    func _beginTerminalHandoffForTesting(expectsStopNotification: Bool) {
        guard let generation = beginTerminalIfNeeded() else { return }
        if expectsStopNotification {
            expectStopNotification(generation: generation)
        }
    }

    func _markTerminalCallbackDeliveredForTesting() {
        markTerminalCallbackDelivered()
    }

    var _terminalHandoffForTesting: (isPending: Bool, restartRequested: Bool) {
        runLock.lock()
        let value = (runLifecycle.isStopping, runLifecycle.restartRequested)
        runLock.unlock()
        return value
    }

    func _handleLifecycleActionForTesting(_ action: CameraLifecycleAction) {
        onSessionQueueSync { publish(action) }
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
        setLastVideoSampleBuffer(nil)
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
        if configuration.video.formatSelectionPolicy == .requireRequested || configuration.video.colorPolicy != .sourceCompatible { return .inputPriority }
        switch configuration.captureMode {
        case .photo:
            return configuration.photo.sessionPreset
        case .video, .videoWithoutAudio:
            return configuration.video.sessionPreset
        }
    }

    private func acquireRunAudioLease() throws {
        guard configuration.audio.managesSession(for: configuration.captureMode) else { return }
        if try audioSessionController.activateForRun(prefersIndependentSession: configuration.audio.prefersIndependentSession) { ownsRunAudioLease = true }
    }

    private func releaseRunAudioLease() {
        if ownsRunAudioLease {
            audioSessionController.deactivate()
            ownsRunAudioLease = audioSessionController.isActive
        }
    }

    private func streamClockTime() -> CMTime? {
        if #available(iOS 15.4, macCatalyst 15.4, tvOS 17.0, *) {
            return session.synchronizationClock.map(CMClockGetTime)
        }
        #if os(iOS)
        if #available(macCatalyst 14.0, *) { return session.masterClock.map(CMClockGetTime) }
        #endif
        return nil
    }
    private func setFramesReady(_ ready: Bool, minimumTime: CMTime?) {
        frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }
        framesAreReady = ready; earliestFrameTime = minimumTime
        if !ready { setLastVideoSampleBuffer(nil) }
    }
    private func publishReady() {
        guard currentActiveRunGeneration() != nil else { return }
        if configuration.video.formatSelectionPolicy == .requireRequested,
           let actual = resolvedVideoSpecification, !configuration.video.accepts(actual) {
            finishRuntimeFailure(CameraVideoSpecificationError.unsupportedSpecification)
            return
        }
        setFramesReady(true, minimumTime: streamClockTime())
        publish(.didStartRunning)
    }
    private func configureTransaction(_ body: () throws -> Void) throws {
        frameDeliveryFence.lock(); let wasReady = framesAreReady; frameDeliveryFence.unlock()
        setFramesReady(false, minimumTime: nil)
        defer { if wasReady && isSessionConfigured && session.isRunning && currentActiveRunGeneration() != nil { setFramesReady(true, minimumTime: streamClockTime()) } }
        let video = videoInput; let audio = audioInput; let position = currentPosition
        let metadata = metadataOutput; let depth = depthDataOutput; let synchronizer = outputSynchronizer
        let settings = videoOutput.videoSettings; let discards = videoOutput.alwaysDiscardsLateVideoFrames
        let configured = isSessionConfigured
        let transaction = CameraCaptureTransaction(session: session)
        configurationTransaction = transaction; defer { configurationTransaction = nil }
        do { try transaction.run(body) }
        catch {
            let restored = !(error is CameraCaptureTransaction.Failure)
            videoInput = video.flatMap { previous in session.inputs.contains(where: { $0 === previous }) ? previous : nil }
            audioInput = audio.flatMap { previous in session.inputs.contains(where: { $0 === previous }) ? previous : nil }
            currentPosition = position
            metadataOutput = metadata; depthDataOutput = depth; outputSynchronizer = synchronizer
            videoOutput.videoSettings = settings; videoOutput.alwaysDiscardsLateVideoFrames = discards
            isSessionConfigured = configured && restored
            if !configured { photoOutput = AVCapturePhotoOutput() }
            applyCurrentConnections(); installDeviceObservers()
            throw error
        }
    }
    private func ensureSessionConfigured() throws {
        guard !isSessionConfigured else { return }
        try configureTransaction {
            self.applySessionPreset()
            self.session.automaticallyConfiguresApplicationAudioSession = false
            try self.configureVideoInput(position: self.currentPosition)
            try self.configureVideoColorPolicy()
            try self.configureAudioInputIfNeeded()
            try self.configureVideoOutput()
            try self.configureAudioOutputIfNeeded()
            try self.configurePhotoOutput()
            try self.configureMetadataOutputIfNeeded()
            try self.configureDepthOutputIfNeeded()
            try self.connectPreviewIfNeeded()
            self.applyCurrentConnections()
            try self.applyInitialDeviceConfigurationIfNeeded()
            self.installDeviceObservers()
            self.isSessionConfigured = true
        }
    }

    private func configureVideoInput(position: CameraPosition) throws {
        let resolvedPosition = position == .unspecified ? .back : position
        guard let device = findVideoDevice(position: resolvedPosition) else {
            throw CameraSourceError.captureDeviceUnavailable(position: resolvedPosition, preferredDeviceTypes: configuration.preferredDeviceTypes)
        }
        configurationTransaction?.watch(device)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSourceError.cannotAddInput(.video)
        }
        if usesExplicitConnections { session.addInputWithNoConnections(input) } else { session.addInput(input) }
        videoInput = input
        currentPosition = resolvedPosition
    }

    private func replaceVideoInput(position: CameraPosition) throws {
        try configureTransaction {
            if let previous = self.videoInput { self.session.removeInput(previous); self.videoInput = nil }
            try self.configureVideoInput(position: position)
            try self.configureVideoColorPolicy()
            try self.configureVideoPixelFormat()
            try self.reconnectVideoOutputsIfNeeded()
            try self.configureDepthOutputIfNeeded()
            try self.connectPreviewIfNeeded()
            self.applyCurrentConnections()
            try self.applyInitialDeviceConfigurationIfNeeded()
            self.installDeviceObservers()
        }
    }
    private var usesExplicitConnections: Bool {
        if #available(iOS 13.0, *) { return session is AVCaptureMultiCamSession }
        return false
    }
    private func connect(_ output: AVCaptureOutput, type: AVMediaType) throws {
        guard usesExplicitConnections else { return }
        let input = type == .audio ? audioInput : videoInput
        guard let port = input?.ports.first(where: { $0.mediaType == type }) else { throw CameraSourceError.cannotAddOutput(type) }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { throw CameraSourceError.cannotAddOutput(type) }
        session.addConnection(connection)
    }
    private func add(_ output: AVCaptureOutput, type: AVMediaType) throws {
        if usesExplicitConnections { session.addOutputWithNoConnections(output) } else { session.addOutput(output) }
        try connect(output, type: type)
    }
    private func setCaptureConnectionsEnabled(_ enabled: Bool) {
        let outputs: [AVCaptureOutput] = [videoOutput, audioOutput, photoOutput] + ([metadataOutput, depthDataOutput] as [AVCaptureOutput?]).compactMap { $0 }
        outputs.flatMap(\.connections).forEach { $0.isEnabled = enabled }
        previewLayer.connection?.isEnabled = enabled && nativePreviewEnabled
    }
    private func connectPreviewIfNeeded() throws {
        guard usesExplicitConnections, previewLayer.connection == nil else { return }
        guard let port = videoInput?.ports.first(where: { $0.mediaType == .video }) else { throw CameraSourceError.cannotAddInput(.video) }
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(connection) else { throw CameraSourceError.cannotAddOutput(.video) }
        session.addConnection(connection)
    }
    private func reconnectVideoOutputsIfNeeded() throws {
        guard usesExplicitConnections else { return }
        for output in [videoOutput, photoOutput] as [AVCaptureOutput] where session.outputs.contains(where: { $0 === output }) {
            for connection in output.connections { session.removeConnection(connection) }
            try connect(output, type: .video)
        }
        if let metadataOutput {
            for connection in metadataOutput.connections { session.removeConnection(connection) }
            try connect(metadataOutput, type: .video)
        }
    }

    private func configureAudioInputIfNeeded() throws {
        guard configuration.captureMode.includesAudio else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraSourceError.cannotAddInput(.audio)
        }
        configurationTransaction?.watch(device)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSourceError.cannotAddInput(.audio)
        }
        if usesExplicitConnections { session.addInputWithNoConnections(input) } else { session.addInput(input) }
        audioInput = input
    }

    private func configureVideoColorPolicy() throws {
        let policy = configuration.video.colorPolicy
        guard policy != .hdrPQ, !policy.isHDR || configuration.video.codec == .hevc else {
            throw CameraSourceError.unsupportedFeature("原生 HDR 采集需要 HLG 和 HEVC。")
        }
        guard let device = videoInput?.device else { throw CameraVideoSpecificationError.unsupportedSpecification }
        let formats = device.formats
        let candidates = formats.map { format -> CameraVideoFormatCandidate in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            var colors: [VideoExportColorPolicy] = [.sourceCompatible]
            if format.supportedColorSpaces.contains(.sRGB) { colors.append(.standardBT709) }
            if format.supportedColorSpaces.contains(.P3_D65) { colors.append(.standardDisplayP3) }
            if #available(iOS 14.1, *), format.supportedColorSpaces.contains(.HLG_BT2020) { colors.append(.hdrHLG) }
            return CameraVideoFormatCandidate(width: Int(size.width), height: Int(size.height), frameRateRanges: format.videoSupportedFrameRateRanges.map {
                CameraFrameRateRange(minimumFramesPerSecond: $0.minFrameRate, maximumFramesPerSecond: $0.maxFrameRate)
            }, colorPolicies: colors)
        }
        guard let index = try configuration.video.preferredFormatIndex(in: candidates, currentIndex: formats.firstIndex(of: device.activeFormat)) else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = formats[index]
        switch policy {
        case .sourceCompatible: break
        case .standardBT709: device.activeColorSpace = .sRGB
        case .standardDisplayP3: device.activeColorSpace = .P3_D65
        case .hdrHLG:
            guard #available(iOS 14.1, *) else { throw CameraVideoSpecificationError.unsupportedSpecification }
            device.activeColorSpace = .HLG_BT2020
        case .hdrPQ: throw CameraVideoSpecificationError.unsupportedSpecification
        }
        if policy != .sourceCompatible { session.automaticallyConfiguresCaptureDeviceForWideColor = false }
    }

    private func configureVideoPixelFormat() throws {
        guard let type = configuration.video.resolvedPixelFormat(available: videoOutput.availableVideoPixelFormatTypes) else {
            throw CameraSourceError.unsupportedFeature("当前相机输出不支持所请求的像素格式。")
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(type)]
    }

    private func configureVideoOutput() throws {
        videoOutput.alwaysDiscardsLateVideoFrames = configuration.discardsLateVideoFrames
        try configureVideoPixelFormat()
        videoOutput.setSampleBufferDelegate(self, queue: mediaOutputQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraSourceError.cannotAddOutput(.video)
        }
        try add(videoOutput, type: .video)
    }

    private func configureAudioOutputIfNeeded() throws {
        guard configuration.captureMode.includesAudio else { return }
        audioOutput.setSampleBufferDelegate(self, queue: mediaOutputQueue)
        guard session.canAddOutput(audioOutput) else {
            throw CameraSourceError.cannotAddOutput(.audio)
        }
        try add(audioOutput, type: .audio)
    }

    private func configurePhotoOutput() throws {
        guard session.canAddOutput(photoOutput) else {
            if configuration.captureMode != .photo { return }
            throw CameraSourceError.cannotAddOutput(.video)
        }
        try add(photoOutput, type: .video)
        photoOutput.isHighResolutionCaptureEnabled = configuration.photo.isHighResolutionEnabled
        prepareMaximumPhotoDimensions()
        if #available(iOS 13.0, *) {
            photoOutput.maxPhotoQualityPrioritization = configuration.photo.photoQualityMode.avFoundationValue
        }
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
        try add(output, type: .video)
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
        output.setDelegate(self, callbackQueue: mediaOutputQueue)
        guard session.canAddOutput(output) else {
            throw CameraSourceError.cannotAddDepthOutput
        }
        try add(output, type: .depthData)
        depthDataOutput = output
        if let connection = output.connections.first, connection.isVideoOrientationSupported {
            connection.videoOrientation = currentOrientation
        }
        if configuration.advanced.requiresSynchronizedDepthData {
            let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, output])
            synchronizer.setDelegate(self, queue: mediaOutputQueue)
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

    private func prepareMaximumPhotoDimensions() {
        guard configuration.photo.preparesMaximumDimensions else { return }
        if #available(iOS 16.0, *),
           let maximum = videoInput?.device.activeFormat.supportedMaxPhotoDimensions.max(by: {
               Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
           }) {
            if photoOutput.maxPhotoDimensions.width != maximum.width || photoOutput.maxPhotoDimensions.height != maximum.height {
                photoOutput.maxPhotoDimensions = maximum
            }
        }
    }

    private func applyInitialDeviceConfigurationIfNeeded() throws {
        guard let device = videoInput?.device else { return }
        prepareMaximumPhotoDimensions()
        controlConfigurationRevision &+= 1
        setLastVideoSampleBuffer(nil)
        do {
            try device.lockForConfiguration()
        } catch {
            if configuration.video.formatSelectionPolicy == .requireRequested { throw error }
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
        if let range = configuration.video.preferredFrameRateRange,
           device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
               $0.minFrameRate <= range.minimumFramesPerSecond && $0.maxFrameRate >= range.maximumFramesPerSecond
           }) {
            let durations = try range.frameDurations()
            device.activeVideoMinFrameDuration = durations.minimum
            device.activeVideoMaxFrameDuration = durations.maximum
        } else if configuration.video.preferredFrameRateRange != nil, configuration.video.formatSelectionPolicy == .requireRequested {
            throw CameraVideoSpecificationError.unsupportedSpecification
        }
        if configuration.video.formatSelectionPolicy == .requireRequested {
            guard let actual = resolvedVideoSpecification, configuration.video.accepts(actual) else {
                throw CameraVideoSpecificationError.unsupportedSpecification
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

    private func mediaSourceDelegatesSnapshot(delivery: MediaSourceDelegateDelivery? = nil) -> [MediaSourceDelegate] {
        delegateLock.lock()
        additionalDelegates = additionalDelegates.filter { $0.value.value != nil }
        var delegates = additionalDelegates.values.filter { delivery == nil || $0.delivery == delivery }.compactMap(\.value)
        if delivery != .processing, let primaryDelegate,
           delegates.contains(where: { $0 === primaryDelegate }) == false {
            delegates.append(primaryDelegate)
        }
        delegateLock.unlock()
        return delegates
    }

    private func notifyDelegatesOfFailure(_ error: Error) {
        mediaSourceDelegatesSnapshot().forEach { delegate in
            delegate.mediaSource(self, didFail: error)
        }
    }

    private func notifyDelegatesOfFinish(_ delegates: [MediaSourceDelegate]? = nil) {
        (delegates ?? mediaSourceDelegatesSnapshot()).forEach { delegate in
            delegate.mediaSourceDidFinish(self)
        }
    }

    private func resolvedFlashMode() -> AVCaptureDevice.FlashMode {
        let preferred = deviceController.preferredFlashMode
        guard photoOutput.supportedFlashModes.contains(preferred) else {
            return .off
        }
        return preferred
    }

    private func acceptsStreamTime(_ time: CMTime?) -> Bool {
        frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }
        guard framesAreReady, let generation = currentActiveRunGeneration(), frameIngressGate.acceptsFrames(in: generation), !isPaused else { return false }
        if let earliestFrameTime, let time, time.isNumeric, time < earliestFrameTime { return false }
        return true
    }

    private func emit(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        frameDeliveryFence.lock()
        guard acceptsStreamTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) else { frameDeliveryFence.unlock(); return }
        frameIndex += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        lastPresentationTime = presentationTime
        lastMediaType = mediaType.rawValue
        if mediaType == .video {
            setLastVideoSampleBuffer(sampleBuffer)
        }
        let frame = SampleBufferFrame(
            sampleBuffer: sampleBuffer,
            metadata: FrameMetadata(
                presentationTime: presentationTime,
                duration: duration.isValid ? duration : nil,
                sourceTime: presentationTime,
                frameIndex: frameIndex,
                captureObservation: mediaType == .video ? previewHardwareObservation() : nil,
                receivedHostTimeSeconds: ProcessInfo.processInfo.systemUptime,
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
        let mediaKind: CameraFrameIngressMediaKind = mediaType == .video ? .video : .audio
        let frameTransfer = CameraCallbackTransfer(frame)
        let generation = currentActiveRunGeneration()
        let hasObservers = frameHandler != nil || !mediaSourceDelegatesSnapshot(delivery: .main).isEmpty
        let observerToken = hasObservers ? observerIngressGate.admit(mediaKind: mediaKind, branchCount: 1) : nil
        let ingressToken = frameIngressGate.admit(mediaKind: mediaKind, branchCount: 1)
        frameDeliveryFence.unlock()
        if let observerToken {
            DispatchQueue.main.async {
                defer { self.observerIngressGate.completeBranch(for: observerToken) }
                guard self.observerIngressGate.isActive(observerToken) else { return }
                self.frameHandler?(frameTransfer.value)
                for delegate in self.mediaSourceDelegatesSnapshot(delivery: .main) {
                    guard self.observerIngressGate.isActive(observerToken) else { break }
                    delegate.mediaSource(self, didOutput: frameTransfer.value)
                }
            }
        }
        guard let ingressToken else {
            guard let generation, frameIngressGate.acceptsFrames(in: generation) else { return }
            let pressure = frameIngressGate.snapshot
            if mediaKind == .audio, pressure.inFlightAudioFrameCount >= pressure.maximumInFlightAudioFrameCount {
                self.mediaSourceDelegatesSnapshot(delivery: .processing).forEach {
                    $0.mediaSource(self, audioDeliveryFailed: MediaCoreError.audioDeliveryOverflow)
                }
            }
            return
        }
        processingQueue.async {
            guard self.frameIngressGate.isActive(ingressToken) else { return }
            CameraFrameDistributor.deliver(frameTransfer.value, source: self,
                delegates: self.mediaSourceDelegatesSnapshot(delivery: .processing), output: self.outputNode,
                shouldContinue: { self.frameIngressGate.isActive(ingressToken) },
                completion: { self.frameIngressGate.completeBranch(for: ingressToken) })
        }
    }

    private func publish(_ action: CameraLifecycleAction) {
        guard let event = lifecycle.handle(action) else { return }
        let eventTransfer = CameraCallbackTransfer(event)
        state = lifecycle.state
        currentPosition = lifecycle.position
        authorizationStatus = lifecycle.authorizationStatus
        DispatchQueue.main.async {
            let event = eventTransfer.value
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

    private func notifyAuthorizationFailure(generation: UInt64) {
        releaseRunAudioLease()
        sessionOwner.stop(sessionBranchID)
        setLastVideoSampleBuffer(nil)
        let status = Self.authorizationStatus(for: configuration.captureMode)
        publish(.authorizationChanged(status))
        let error = CameraSourceError.authorizationDenied(requestedMediaTypes: configuration.requestedMediaTypes)
        DispatchQueue.main.async {
            guard self.frameIngressGate.isCurrentGeneration(generation) else { return }
            self.notifyDelegatesOfFailure(error)
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
        previewLayer.connection?.isEnabled = nativePreviewEnabled
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

    private func beginRunIfNeeded() -> UInt64? {
        frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.begin {
            framesAreReady = false; earliestFrameTime = nil
            setLastVideoSampleBuffer(nil)
            observerIngressGate.reset()
            return frameIngressGate.reset()
        }
    }

    private func beginAuthorizationRequestIfNeeded() -> UInt64? {
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.begin {
            observerIngressGate.rejectFurtherFrames()
            return frameIngressGate.rejectFurtherFrames()
        }
    }

    private func completeAuthorizationRequest(generation: UInt64) -> Bool {
        runLock.lock()
        defer { runLock.unlock() }
        guard frameIngressGate.isCurrentGeneration(generation) else { return false }
        return runLifecycle.completeAuthorization(generation: generation)
    }

    private func beginTerminalIfNeeded() -> UInt64? {
        frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }
        framesAreReady = false; earliestFrameTime = nil
        setLastVideoSampleBuffer(nil)
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.beginTerminal {
            observerIngressGate.rejectFurtherFrames()
            return frameIngressGate.rejectFurtherFrames()
        }
    }

    private func invalidateRunForFailure() -> UInt64 {
        frameDeliveryFence.lock(); defer { frameDeliveryFence.unlock() }
        framesAreReady = false; earliestFrameTime = nil
        setLastVideoSampleBuffer(nil)
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.invalidate {
            observerIngressGate.rejectFurtherFrames()
            return frameIngressGate.rejectFurtherFrames()
        }
    }

    private func deferStartUntilTerminalHandoffIfNeeded() -> Bool {
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.deferStartIfStopping()
    }

    private func expectStopNotification(generation: UInt64) {
        runLock.lock()
        runLifecycle.expectStop(generation: generation)
        runLock.unlock()
    }

    private func currentActiveRunGeneration() -> UInt64? {
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.activeGeneration
    }

    private func isActiveRunGeneration(_ generation: UInt64) -> Bool {
        runLock.lock()
        defer { runLock.unlock() }
        return runLifecycle.isCurrent(generation)
    }

    /// `startRunning()` 可能阻塞，不能在持有 runLock 时调用（AVFoundation 可能同步回调通知）。
    /// 若并发 stop 在调用期间失效了 generation，则在 session owner 上立即回收本次启动。
    private func startSessionIfRunIsActive(generation: UInt64) -> Bool {
        guard isActiveRunGeneration(generation) else { return false }
        sessionOwner.start(sessionBranchID)
        guard isActiveRunGeneration(generation) else {
            sessionOwner.stop(sessionBranchID)
            return false
        }
        return true
    }

    private func consumeExpectedStopNotification() -> Bool {
        runLock.lock()
        let result = runLifecycle.consumeExpectedStop()
        runLock.unlock()
        if result.restart { start() }
        return result.consumed
    }

    private func markTerminalCallbackDelivered() {
        runLock.lock()
        let shouldRestart = runLifecycle.markCallbackDelivered()
        runLock.unlock()
        if shouldRestart { start() }
    }

    private func onSessionQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            work()
        } else {
            sessionQueue.async(execute: work)
        }
    }

    private func onSessionQueueSync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil { return try work() }
        return try sessionQueue.sync(execute: work)
    }

    private func startObservingNotifications() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionDidStartRunning, object: session, queue: nil) { [weak self] _ in
                guard let self, let runGeneration = self.currentActiveRunGeneration() else { return }
                self.sessionQueue.async {
                    guard self.isActiveRunGeneration(runGeneration) else { return }
                    self.publishReady()
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionDidStopRunning, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.onSessionQueue {
                    guard !self.consumeExpectedStopNotification() else { return }
                    guard self.beginTerminalIfNeeded() != nil else { return }
                    let terminalDelegates = CameraCallbackTransfer(self.mediaSourceDelegatesSnapshot())
                    self.publish(.didStopRunning)
                    DispatchQueue.main.async {
                        self.notifyDelegatesOfFinish(terminalDelegates.value)
                        self.markTerminalCallbackDelivered()
                    }
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] notification in
                guard let self, let runGeneration = self.currentActiveRunGeneration() else { return }
                self.onSessionQueue {
                    guard self.isActiveRunGeneration(runGeneration) else { return }
                    self.handleRuntimeError(notification)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
                guard let self, let generation = self.currentActiveRunGeneration() else { return }
                self.onSessionQueue {
                    guard self.isActiveRunGeneration(generation) else { return }
                    self.handleSessionInterruption(isRecordingActive: self.isRecordingActiveProvider?() == true)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
                guard let self, let generation = self.currentActiveRunGeneration() else { return }
                self.onSessionQueue {
                    guard self.isActiveRunGeneration(generation) else { return }
                    self.handleSessionInterruptionEnded()
                }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                self?.onSessionQueue { self?.updateCurrentOrientation() }
            }
        )
        notificationObservers.append(
            center.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: nil, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { self?.deviceController.notifySubjectAreaChanged() }
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
            self?.onSessionQueue { self?.handleAudioSessionEvent(event) }
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
        if isRecoverable {
            publish(.runtimeError(isRecoverable: true, description: error?.localizedDescription))
            guard let runGeneration = currentActiveRunGeneration(),
                  authorizationStatus == .authorized else { return }
            CameraSessionRecovery.run(isCurrent: { self.isActiveRunGeneration(runGeneration) }, configure: {
                try self.configureTransaction {
                    try self.configureVideoColorPolicy()
                    try self.configureVideoPixelFormat()
                    self.applyCurrentConnections()
                    try self.applyInitialDeviceConfigurationIfNeeded()
                    self.installDeviceObservers()
                }
            }, restart: {
                guard self.startSessionIfRunIsActive(generation: runGeneration) else { return false }
                guard self.session.isRunning else { throw CameraPhotoCaptureError.sessionUnavailable }
                return true
            }, ready: {
                self.publishReady()
            }, failed: {
                self.finishRuntimeFailure($0)
            })
            return
        }
        guard let error else { return }
        finishRuntimeFailure(error)
    }

    private func finishRuntimeFailure(_ error: Error) {
        guard let terminalGeneration = beginTerminalIfNeeded() else { return }
        publish(.runtimeError(isRecoverable: false, description: error.localizedDescription))
        setCaptureConnectionsEnabled(false)
        setLastVideoSampleBuffer(nil)
        let terminalDelegates = CameraCallbackTransfer(mediaSourceDelegatesSnapshot())
        sessionOwner.stop(sessionBranchID) {
            expectStopNotification(generation: terminalGeneration)
        }
        releaseRunAudioLease()
        DispatchQueue.main.async {
            terminalDelegates.value.forEach { $0.mediaSource(self, didFail: error) }
            self.markTerminalCallbackDelivered()
        }
    }

    private func handleSessionInterruption(isRecordingActive: Bool) {
        guard currentActiveRunGeneration() != nil, lifecycle.canBeginInterruption else { return }
        if !isPaused {
            isPaused = true
            shouldResumeAfterInterruption = true
        } else {
            shouldResumeAfterInterruption = false
        }
        publish(isRecordingActive ? .wasInterruptedWhileRecording : .wasInterrupted)
    }

    private func handleSessionInterruptionEnded() {
        guard currentActiveRunGeneration() != nil,
              state == .interrupted || state == .interruptedWhileRecording else { return }
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
        case .interruptionBegan:
            guard configuration.audio.managesSession(for: configuration.captureMode) else { return }
            handleSessionInterruption(isRecordingActive: isRecordingActiveProvider?() == true)
        case .interruptionEnded(let shouldResume):
            guard configuration.audio.managesSession(for: configuration.captureMode) else { return }
            if shouldResume { handleSessionInterruptionEnded() }
        case .activationFailed(let description):
            if currentActiveRunGeneration() != nil, configuration.captureMode.includesAudio {
                finishRuntimeFailure(NSError(domain: "Kakapos.CameraAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: description]))
            }
        case .didActivate, .didDeactivate: break
        }
    }

    private func installDeviceObservers() {
        deviceObservers.removeAll()
        guard let device = videoInput?.device else { return }
        deviceObservers.append(
            device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.sessionQueue.async { self?.deviceController.emit(.focusAdjustmentChanged(value)) }
            }
        )
        deviceObservers.append(
            device.observe(\.isAdjustingExposure, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.sessionQueue.async { self?.deviceController.emit(.exposureAdjustmentChanged(value)) }
            }
        )
        deviceObservers.append(
            device.observe(\.lensPosition, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.sessionQueue.async { self?.deviceController.emit(.lensPositionChanged(value)) }
            }
        )
        deviceObservers.append(
            device.observe(\.exposureDuration, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.sessionQueue.async { self?.deviceController.emit(.exposureDurationChanged(value)) }
            }
        )
        deviceObservers.append(
            device.observe(\.iso, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                self?.sessionQueue.async { self?.deviceController.emit(.isoChanged(value)) }
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
        guard output.connections.contains(where: { $0 === connection }) else { return }
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
        guard let delivery = photoDelivery(photo.resolvedSettings.uniqueID) else { return }
        if let error {
            delivery.result.stage(.failure(error))
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
        guard let data = photo.fileDataRepresentation() else {
            delivery.result.stage(.failure(CameraPhotoCaptureError.missingResource))
            return
        }
        let resource: CameraPhotoCaptureResource
        do {
            resource = try CameraPhotoCaptureResource(encodedData: data, metadata: photo.metadata,
                origin: .nativePhoto, isRaw: photo.isRawPhoto,
                resolvedFlashEnabled: photo.resolvedSettings.isFlashEnabled, photoTimestampSeconds: photo.timestamp.seconds)
        } catch {
            delivery.result.stage(.failure(error))
            return
        }
        let result = CameraPhotoCaptureResult(
            resource: resource,
            depthDataDelivered: deliveredDepthData,
            portraitEffectsMatteDelivered: deliveredPortraitEffectsMatte
        )
        delivery.result.stage(.success(result))
    }
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completePhotoDelivery(resolvedSettings.uniqueID, error: error)
    }
}

extension CameraSource: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard metadataOutput === output, acceptsStreamTime(metadataObjects.first?.time) else { return }
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
        guard depthDataOutput === output, acceptsStreamTime(timestamp) else { return }
        advancedOutput.emitDepthData(.init(timestamp: timestamp, depthData: depthData, isSynchronized: false))
    }
}

@available(iOS 11.0, *)
extension CameraSource: AVCaptureDataOutputSynchronizerDelegate {
    public func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard outputSynchronizer === synchronizer, acceptsStreamTime(nil),
              let synchronizedSampleBuffer = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }
        if synchronizedSampleBuffer.sampleBufferWasDropped == false {
            emit(sampleBuffer: synchronizedSampleBuffer.sampleBuffer, mediaType: .video)
        }
        if let depthDataOutput,
           let synchronizedDepth = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
           synchronizedDepth.depthDataWasDropped == false, acceptsStreamTime(synchronizedDepth.timestamp) {
            advancedOutput.emitDepthData(.init(timestamp: synchronizedDepth.timestamp, depthData: synchronizedDepth.depthData, isSynchronized: true))
        }
    }
}
#endif

// 主队列回调持有不可变载荷；delegate 的调用仍只在既有主队列执行。
private struct CameraCallbackTransfer<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
