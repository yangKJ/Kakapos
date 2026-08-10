//
//  CameraEngine.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public enum CameraEngineError: Error, LocalizedError, Equatable {
    case recordingControllerUnavailable

    public var errorDescription: String? {
        switch self {
        case .recordingControllerUnavailable:
            return "Recording controller unavailable"
        }
    }
}

public final class CameraEngine {
    public let source: CameraSource
    public let deviceController: CameraDeviceController
    public let advancedOutput: CameraAdvancedOutput
    public let audioSessionController: CameraAudioSessionController
    public private(set) var previewController: CameraPreviewController?
    public private(set) var recordingController: CameraRecordingController?
    public private(set) var recentEvents: [String] = []

    private var recordingEventObserver: UUID?

    public var previewLayer: AVCaptureVideoPreviewLayer {
        source.previewLayer
    }

    public var snapshot: CameraSource.Snapshot {
        source.snapshot
    }

    public var summaryText: String {
        source.summaryText
    }

    public var capabilitySnapshot: CameraCapabilitySnapshot {
        source.capabilitySnapshot
    }

    public var capabilitySummaryText: String {
        source.capabilitySnapshot.summaryText
    }

    public var deviceSnapshot: CameraDeviceSnapshot {
        deviceController.snapshot
    }

    public var deviceSummaryText: String {
        deviceController.snapshot.summaryText
    }

    public var previewSummaryText: String? {
        previewController?.summaryText
    }

    public var recordingSummaryText: String? {
        recordingController?.summaryText
    }

    public var diagnosticsSnapshot: CameraDiagnosticsSnapshot {
        CameraDiagnosticsSnapshot(
            sessionSummaryText: summaryText,
            deviceSummaryText: deviceSummaryText,
            previewSummaryText: previewSummaryText,
            recordingSummaryText: recordingSummaryText,
            capabilitySummaryText: capabilitySummaryText,
            capabilityGateStatuses: capabilitySnapshot.gateStatuses,
            advancedEventSummaryText: advancedOutput.latestEventSummaryText,
            recentEvents: recentEvents
        )
    }

    public var recordedClip: RecordedClip? {
        recordingController?.recordedClip
    }

    public init(configuration: CameraCaptureConfiguration = .init()) throws {
        let source = try CameraSource(configuration: configuration)
        self.source = source
        self.deviceController = source.deviceController
        self.advancedOutput = source.advancedOutput
        self.audioSessionController = source.audioSessionController
        wireDiagnostics()
    }

    public func makePreviewController(
        mode: CameraPreviewController.Mode = .raw,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: PreviewSink.Handler? = nil
    ) -> CameraPreviewController {
        let controller = CameraPreviewController(
            source: source,
            mode: mode,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
        previewController = controller
        return controller
    }

    public func makeRecordingController(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws -> CameraRecordingController {
        let previousController = recordingController
        let controller = try CameraRecordingController(
            source: source,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
        source.isRecordingActiveProvider = { [weak controller] in
            controller?.isRecordingActive ?? false
        }
        recordingController = controller
        wireRecordingDiagnostics(for: controller, previousController: previousController)
        return controller
    }

    public func start() {
        audioSessionController.activate(prefersIndependentSession: source.configuration.audio.prefersIndependentSession)
        source.start()
        previewController?.start()
    }

    public func startPreview(
        mode: CameraPreviewController.Mode = .processed,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: PreviewSink.Handler? = nil
    ) -> CameraPreviewController {
        let controller = previewController ?? makePreviewController(
            mode: mode,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
        audioSessionController.activate(prefersIndependentSession: source.configuration.audio.prefersIndependentSession)
        source.start()
        controller.start()
        return controller
    }

    public func pause() {
        source.pause()
        previewController?.pause()
        recordingController?.pause()
    }

    public func resume() {
        source.resume()
        previewController?.resume()
        recordingController?.resume()
    }

    public func stop() {
        source.stop()
        previewController?.stop()
        recordingController?.stop()
        audioSessionController.deactivate()
    }

    public func cancel() {
        source.cancel()
        previewController?.stop()
        recordingController?.cancel()
        audioSessionController.deactivate()
    }

    @discardableResult
    public func startRecording(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws -> CameraRecordingController {
        let controller: CameraRecordingController
        if let recordingController,
           [RecorderSink.State.preparing, .recording, .paused].contains(recordingController.state) {
            controller = recordingController
            controller.start()
        } else {
            controller = try makeRecordingController(
                outputURL: outputURL,
                fileType: fileType,
                processors: processors
            )
            audioSessionController.activate(prefersIndependentSession: source.configuration.audio.prefersIndependentSession)
            source.start()
            previewController?.start()
            controller.start()
        }
        return controller
    }

    public func stopRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        guard let recordingController else {
            completion(.failure(CameraEngineError.recordingControllerUnavailable))
            return
        }
        recordingController.stopRecording { [weak self] result in
            self?.previewController?.stop()
            self?.source.stop()
            self?.audioSessionController.deactivate()
            completion(result)
        }
    }

    public func cancelRecording() {
        recordingController?.cancel()
        previewController?.stop()
        source.cancel()
        audioSessionController.deactivate()
    }

    @discardableResult
    public func switchCameraPosition() -> Bool {
        source.switchCameraPosition()
    }

    public func capturePhoto() {
        source.capturePhoto()
    }

    public func capturePhoto(handler: @escaping (CameraPhotoCaptureResult) -> Void) {
        source.photoCaptureHandler = handler
        source.capturePhoto()
    }

    @discardableResult
    public func setFocusMode(_ focusMode: CameraFocusMode) throws -> CameraDeviceSnapshot {
        try deviceController.setFocusMode(focusMode)
    }

    @discardableResult
    public func setLensPosition(_ lensPosition: Float) throws -> CameraDeviceSnapshot {
        try deviceController.setLensPosition(lensPosition)
    }

    @discardableResult
    public func setZoomFactor(_ zoomFactor: CGFloat) throws -> CameraDeviceSnapshot {
        try deviceController.setZoomFactor(zoomFactor)
    }

    @discardableResult
    public func rampZoomFactor(to zoomFactor: CGFloat, rate: Float = 8) throws -> CameraDeviceSnapshot {
        try deviceController.rampZoomFactor(to: zoomFactor, rate: rate)
    }

    @discardableResult
    public func setFocusPoint(_ point: CGPoint, mode: CameraFocusMode? = nil) throws -> CameraDeviceSnapshot {
        try deviceController.setFocusPoint(point, mode: mode)
    }

    @discardableResult
    public func setExposurePoint(_ point: CGPoint, mode: CameraExposureMode? = nil) throws -> CameraDeviceSnapshot {
        try deviceController.setExposurePoint(point, mode: mode)
    }

    @discardableResult
    public func setExposureBias(_ bias: Float) throws -> CameraDeviceSnapshot {
        try deviceController.setExposureBias(bias)
    }

    @discardableResult
    public func setExposureMode(_ exposureMode: CameraExposureMode) throws -> CameraDeviceSnapshot {
        try deviceController.setExposureMode(exposureMode)
    }

    @discardableResult
    public func setCustomExposure(duration: CMTime, iso: Float) throws -> CameraDeviceSnapshot {
        try deviceController.setCustomExposure(duration: duration, iso: iso)
    }

    @discardableResult
    public func setWhiteBalanceMode(_ whiteBalanceMode: CameraWhiteBalanceMode) throws -> CameraDeviceSnapshot {
        try deviceController.setWhiteBalanceMode(whiteBalanceMode)
    }

    @discardableResult
    public func lockWhiteBalanceGains(red: Float, green: Float, blue: Float) throws -> CameraDeviceSnapshot {
        try deviceController.lockWhiteBalanceGains(red: red, green: green, blue: blue)
    }

    @discardableResult
    public func setSmoothAutoFocusEnabled(_ isEnabled: Bool) throws -> CameraDeviceSnapshot {
        try deviceController.setSmoothAutoFocusEnabled(isEnabled)
    }

    @discardableResult
    public func resetSubjectAreaMonitoring(enabled: Bool = true) throws -> CameraDeviceSnapshot {
        try deviceController.resetSubjectAreaMonitoring(enabled: enabled)
    }

    @discardableResult
    public func setTorchActive(_ isActive: Bool, level: Float = 1) throws -> CameraDeviceSnapshot {
        try deviceController.setTorchActive(isActive, level: level)
    }

    @discardableResult
    public func setPreferredFlashMode(_ flashMode: AVCaptureDevice.FlashMode) -> CameraDeviceSnapshot {
        deviceController.setPreferredFlashMode(flashMode)
    }

    @discardableResult
    public func selectPreferredDeviceType(_ deviceType: CameraDeviceType) -> CameraDeviceSnapshot {
        deviceController.selectPreferredDeviceType(deviceType)
    }

    @discardableResult
    public func selectFrameRateRange(_ range: CameraFrameRateRange) throws -> CameraDeviceSnapshot {
        try deviceController.selectFrameRateRange(range)
    }

    private func wireDiagnostics() {
        source.addSessionEventObserver { [weak self] event in
            self?.appendEvent(String(describing: event))
            self?.synchronizeControllers(for: event)
        }
        source.addAuthorizationObserver { [weak self] status in
            self?.appendEvent("auth \(status)")
        }
        deviceController.addEventObserver { [weak self] event in
            self?.appendEvent(String(describing: event))
        }
        advancedOutput.addEventObserver { [weak self] event in
            self?.appendEvent(event.summaryText)
        }
        audioSessionController.addEventObserver { [weak self] event in
            self?.appendEvent(String(describing: event))
        }
    }

    private func wireRecordingDiagnostics(for controller: CameraRecordingController, previousController: CameraRecordingController?) {
        if let recordingEventObserver, let previousController {
            previousController.removeEventObserver(recordingEventObserver)
        }
        recordingEventObserver = controller.addEventObserver { [weak self] event in
            self?.appendEvent("recording \(String(describing: event))")
        }
    }

    private func synchronizeControllers(for event: CameraSessionEvent) {
        switch event {
        case .didPause, .wasInterrupted, .wasInterruptedWhileRecording:
            previewController?.pause()
            if recordingController?.state == .recording {
                recordingController?.pause()
            }
        case .didResume:
            previewController?.resume()
            if recordingController?.state == .paused {
                recordingController?.resume()
            }
        case .interruptionEnded:
            if source.snapshot.isPaused == false {
                previewController?.resume()
                if recordingController?.state == .paused {
                    recordingController?.resume()
                }
            }
        case .didStop:
            previewController?.stop()
        case .willStart, .didStart, .willSwitchPosition, .runtimeError, .systemPressureChanged, .audioRouteChanged, .positionChanged, .authorizationChanged:
            break
        }
    }

    private func appendEvent(_ event: String) {
        recentEvents.append(event)
        if recentEvents.count > 20 {
            recentEvents.removeFirst(recentEvents.count - 20)
        }
    }
}
#endif
