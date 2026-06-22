//
//  CameraDeviceController.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
import CoreGraphics

#if canImport(UIKit) && !os(watchOS)
public enum CameraDeviceControlError: Error, LocalizedError, Equatable {
    case deviceUnavailable
    case unsupportedControl(String)
    case cannotLockDevice(String)
    case invalidZoomFactor(CGFloat)

    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "Camera device unavailable"
        case .unsupportedControl(let description):
            return "Unsupported camera control: \(description)"
        case .cannotLockDevice(let description):
            return "Cannot lock camera device for \(description)"
        case .invalidZoomFactor(let zoomFactor):
            return "Invalid zoom factor \(zoomFactor)"
        }
    }
}

public final class CameraDeviceController {
    public typealias DeviceProvider = () -> AVCaptureDevice?
    public typealias PositionProvider = () -> CameraPosition

    public var eventHandler: ((CameraDeviceEvent) -> Void)?
    public private(set) var focusPoint: CGPoint?
    public private(set) var exposurePoint: CGPoint?
    public private(set) var preferredFlashMode: AVCaptureDevice.FlashMode = .off
    public private(set) var preferredDeviceType: CameraDeviceType?

    private let deviceProvider: DeviceProvider
    private let positionProvider: PositionProvider
    private let eventDispatcher = CameraEventDispatcher<CameraDeviceEvent>()

    public init(
        deviceProvider: @escaping DeviceProvider,
        positionProvider: @escaping PositionProvider
    ) {
        self.deviceProvider = deviceProvider
        self.positionProvider = positionProvider
    }

    @discardableResult
    public func addEventObserver(_ handler: @escaping (CameraDeviceEvent) -> Void) -> UUID {
        eventDispatcher.addObserver(handler)
    }

    public func removeEventObserver(_ token: UUID) {
        eventDispatcher.removeObserver(token)
    }

    public var snapshot: CameraDeviceSnapshot {
        guard let device = deviceProvider() else {
            return CameraDeviceSnapshot(
                position: positionProvider(),
                zoomFactor: 1,
                lensPosition: nil,
                exposureBias: nil,
                iso: nil,
                exposureDuration: nil,
                torchActive: false,
                flashAvailable: false,
                torchAvailable: false,
                focusPoint: focusPoint,
                exposurePoint: exposurePoint,
                focusMode: nil,
                exposureMode: nil,
                whiteBalanceMode: nil,
                activeDeviceType: preferredDeviceType?.description,
                subjectAreaMonitoringEnabled: false,
                isAdjustingFocus: false,
                isAdjustingExposure: false,
                whiteBalanceGains: [],
                activeFormatDescription: nil,
                activeFrameRateRange: nil
            )
        }
        let frameRateRange = device.activeVideoMinFrameDuration.isValid && device.activeVideoMaxFrameDuration.isValid
            ? CameraFrameRateRange(
                minimumFramesPerSecond: device.activeVideoMaxFrameDuration.seconds > 0 ? 1 / device.activeVideoMaxFrameDuration.seconds : 0,
                maximumFramesPerSecond: device.activeVideoMinFrameDuration.seconds > 0 ? 1 / device.activeVideoMinFrameDuration.seconds : 0
            )
            : nil
        return CameraDeviceSnapshot(
            position: positionProvider(),
            zoomFactor: device.videoZoomFactor,
            lensPosition: device.isFocusModeSupported(.locked) ? device.lensPosition : nil,
            exposureBias: device.exposureTargetBias,
            iso: device.iso,
            exposureDuration: device.exposureDuration,
            torchActive: device.isTorchActive,
            flashAvailable: device.hasFlash,
            torchAvailable: device.hasTorch,
            focusPoint: focusPoint,
            exposurePoint: exposurePoint,
            focusMode: CameraFocusMode(device.focusMode),
            exposureMode: CameraExposureMode(device.exposureMode),
            whiteBalanceMode: CameraWhiteBalanceMode(device.whiteBalanceMode),
            activeDeviceType: preferredDeviceType?.description ?? device.deviceType.rawValue,
            subjectAreaMonitoringEnabled: device.isSubjectAreaChangeMonitoringEnabled,
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            whiteBalanceGains: [
                device.deviceWhiteBalanceGains.redGain,
                device.deviceWhiteBalanceGains.greenGain,
                device.deviceWhiteBalanceGains.blueGain
            ],
            activeFormatDescription: "\(device.activeFormat.formatDescription)",
            activeFrameRateRange: frameRateRange
        )
    }

    @discardableResult
    public func setZoomFactor(_ zoomFactor: CGFloat) throws -> CameraDeviceSnapshot {
        guard zoomFactor >= 1 else {
            throw CameraDeviceControlError.invalidZoomFactor(zoomFactor)
        }
        return try withLockedDevice(operation: "set zoom factor") { device in
            let resolved = min(max(zoomFactor, 1), device.activeFormat.videoMaxZoomFactor)
            device.videoZoomFactor = resolved
            emit(.zoomFactorChanged(resolved))
        }
    }

    @discardableResult
    public func rampZoomFactor(to zoomFactor: CGFloat, rate: Float = 8) throws -> CameraDeviceSnapshot {
        guard zoomFactor >= 1 else {
            throw CameraDeviceControlError.invalidZoomFactor(zoomFactor)
        }
        return try withLockedDevice(operation: "ramp zoom factor") { device in
            let resolved = min(max(zoomFactor, 1), device.activeFormat.videoMaxZoomFactor)
            device.ramp(toVideoZoomFactor: resolved, withRate: rate)
            emit(.zoomFactorChanged(resolved))
        }
    }

    @discardableResult
    public func setFocusPoint(_ point: CGPoint, mode: CameraFocusMode? = nil) throws -> CameraDeviceSnapshot {
        focusPoint = point
        return try withLockedDevice(operation: "set focus point") { device in
            guard device.isFocusPointOfInterestSupported else {
                throw CameraDeviceControlError.unsupportedControl("focus point")
            }
            if let mode, device.isFocusModeSupported(mode.avFoundationMode) {
                device.focusMode = mode.avFoundationMode
            }
            device.focusPointOfInterest = point
            emit(.focusPointChanged(point))
        }
    }

    @discardableResult
    public func setExposurePoint(_ point: CGPoint, mode: CameraExposureMode? = nil) throws -> CameraDeviceSnapshot {
        exposurePoint = point
        return try withLockedDevice(operation: "set exposure point") { device in
            guard device.isExposurePointOfInterestSupported else {
                throw CameraDeviceControlError.unsupportedControl("exposure point")
            }
            if let mode, device.isExposureModeSupported(mode.avFoundationMode) {
                device.exposureMode = mode.avFoundationMode
            }
            device.exposurePointOfInterest = point
            emit(.exposurePointChanged(point))
        }
    }

    @discardableResult
    public func setExposureBias(_ bias: Float) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "set exposure bias") { device in
            let resolved = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(resolved)
            emit(.exposureBiasChanged(resolved))
        }
    }

    @discardableResult
    public func setFocusMode(_ focusMode: CameraFocusMode) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set focus mode") { device in
            guard device.isFocusModeSupported(focusMode.avFoundationMode) else {
                throw CameraDeviceControlError.unsupportedControl("focus mode \(focusMode)")
            }
            device.focusMode = focusMode.avFoundationMode
            emit(.focusModeChanged(focusMode))
        }
    }

    @discardableResult
    public func setLensPosition(_ lensPosition: Float) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set lens position") { device in
            guard device.isLockingFocusWithCustomLensPositionSupported else {
                throw CameraDeviceControlError.unsupportedControl("lens position")
            }
            let resolved = min(max(lensPosition, 0), 1)
            device.setFocusModeLocked(lensPosition: resolved)
            emit(.lensPositionChanged(resolved))
            emit(.focusModeChanged(.locked))
        }
    }

    @discardableResult
    public func setExposureMode(_ exposureMode: CameraExposureMode) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set exposure mode") { device in
            guard device.isExposureModeSupported(exposureMode.avFoundationMode) else {
                throw CameraDeviceControlError.unsupportedControl("exposure mode \(exposureMode)")
            }
            device.exposureMode = exposureMode.avFoundationMode
            emit(.exposureModeChanged(exposureMode))
        }
    }

    @discardableResult
    public func setCustomExposure(duration: CMTime, iso: Float) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set custom exposure") { device in
            guard device.isExposureModeSupported(.custom) else {
                throw CameraDeviceControlError.unsupportedControl("custom exposure")
            }
            let resolvedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
            device.setExposureModeCustom(duration: duration, iso: resolvedISO)
            emit(.exposureModeChanged(.custom))
            emit(.exposureDurationChanged(duration))
            emit(.isoChanged(resolvedISO))
        }
    }

    @discardableResult
    public func setWhiteBalanceMode(_ whiteBalanceMode: CameraWhiteBalanceMode) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set white balance mode") { device in
            guard device.isWhiteBalanceModeSupported(whiteBalanceMode.avFoundationMode) else {
                throw CameraDeviceControlError.unsupportedControl("white balance mode \(whiteBalanceMode)")
            }
            device.whiteBalanceMode = whiteBalanceMode.avFoundationMode
            emit(.whiteBalanceModeChanged(whiteBalanceMode))
        }
    }

    @discardableResult
    public func lockWhiteBalanceGains(red: Float, green: Float, blue: Float) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "lock white balance gains") { device in
            guard device.isWhiteBalanceModeSupported(.locked) else {
                throw CameraDeviceControlError.unsupportedControl("white balance gains")
            }
            var gains = AVCaptureDevice.WhiteBalanceGains(
                redGain: red,
                greenGain: green,
                blueGain: blue
            )
            gains.redGain = min(max(1, gains.redGain), device.maxWhiteBalanceGain)
            gains.greenGain = min(max(1, gains.greenGain), device.maxWhiteBalanceGain)
            gains.blueGain = min(max(1, gains.blueGain), device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(with: gains)
            emit(.whiteBalanceModeChanged(.locked))
            emit(.whiteBalanceGainsChanged([gains.redGain, gains.greenGain, gains.blueGain]))
        }
    }

    @discardableResult
    public func setSmoothAutoFocusEnabled(_ isEnabled: Bool) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "set smooth auto focus") { device in
            guard device.isSmoothAutoFocusSupported else {
                throw CameraDeviceControlError.unsupportedControl("smooth auto focus")
            }
            device.isSmoothAutoFocusEnabled = isEnabled
            emit(.smoothAutoFocusChanged(isEnabled))
        }
    }

    @discardableResult
    public func resetSubjectAreaMonitoring(enabled: Bool = true) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "reset subject area monitoring") { device in
            device.isSubjectAreaChangeMonitoringEnabled = enabled
            emit(.subjectAreaMonitoringChanged(enabled))
        }
    }

    @discardableResult
    public func setTorchActive(_ isActive: Bool, level: Float = AVCaptureDevice.maxAvailableTorchLevel) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "set torch") { device in
            guard device.hasTorch else {
                throw CameraDeviceControlError.unsupportedControl("torch")
            }
            if isActive {
                try device.setTorchModeOn(level: min(max(level, 0), AVCaptureDevice.maxAvailableTorchLevel))
            } else {
                device.torchMode = .off
            }
            emit(.torchActiveChanged(isActive))
        }
    }

    @discardableResult
    public func setPreferredFlashMode(_ flashMode: AVCaptureDevice.FlashMode) -> CameraDeviceSnapshot {
        preferredFlashMode = flashMode
        emit(.flashModeChanged(flashMode))
        return snapshot
    }

    @discardableResult
    public func selectPreferredDeviceType(_ deviceType: CameraDeviceType) -> CameraDeviceSnapshot {
        preferredDeviceType = deviceType
        return snapshot
    }

    @discardableResult
    public func selectFrameRateRange(_ range: CameraFrameRateRange) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "select frame rate range") { device in
            let minDuration = range.maximumFramesPerSecond > 0 ? CMTime(seconds: 1 / range.maximumFramesPerSecond, preferredTimescale: 600) : .invalid
            let maxDuration = range.minimumFramesPerSecond > 0 ? CMTime(seconds: 1 / range.minimumFramesPerSecond, preferredTimescale: 600) : .invalid
            guard minDuration.isValid, maxDuration.isValid else {
                throw CameraDeviceControlError.unsupportedControl("frame rate range")
            }
            device.activeVideoMinFrameDuration = minDuration
            device.activeVideoMaxFrameDuration = maxDuration
            emit(.frameRateChanged(range))
        }
    }

    @discardableResult
    public func selectFormat(where matches: (AVCaptureDevice.Format) -> Bool) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "select device format") { device in
            guard let format = device.formats.first(where: matches) else {
                throw CameraDeviceControlError.unsupportedControl("matching format")
            }
            device.activeFormat = format
            emit(.formatChanged("\(format.formatDescription)"))
        }
    }

    @discardableResult
    public func selectBestFormat(_ score: (AVCaptureDevice.Format) -> Int) throws -> CameraDeviceSnapshot {
        try withLockedDevice(operation: "select best device format") { device in
            let best = device.formats.max { score($0) < score($1) }
            guard let best else {
                throw CameraDeviceControlError.unsupportedControl("best format")
            }
            device.activeFormat = best
            emit(.formatChanged("\(best.formatDescription)"))
        }
    }

    public func notifySubjectAreaChanged() {
        emit(.subjectAreaChanged)
    }

    public func notifyCleanApertureChanged(_ aperture: CGRect) {
        emit(.cleanApertureChanged(aperture))
    }

    public func notifySystemPressureChanged(_ level: String) {
        emit(.systemPressureChanged(level))
    }

    public func refreshAdjustingState() {
        guard let device = deviceProvider() else { return }
        emit(.focusAdjustmentChanged(device.isAdjustingFocus))
        emit(.exposureAdjustmentChanged(device.isAdjustingExposure))
    }

    func emit(_ event: CameraDeviceEvent) {
        eventHandler?(event)
        eventDispatcher.emit(event)
    }

    private func withLockedDevice(
        operation: String,
        block: (AVCaptureDevice) throws -> Void
    ) throws -> CameraDeviceSnapshot {
        guard let device = deviceProvider() else {
            throw CameraDeviceControlError.deviceUnavailable
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraDeviceControlError.cannotLockDevice(operation)
        }
        defer { device.unlockForConfiguration() }
        try block(device)
        return snapshot
    }
}
#endif
