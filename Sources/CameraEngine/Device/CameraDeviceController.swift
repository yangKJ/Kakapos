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

    private let deviceProvider: DeviceProvider
    private let positionProvider: PositionProvider
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.camera-device-controller")

    public init(
        deviceProvider: @escaping DeviceProvider,
        positionProvider: @escaping PositionProvider
    ) {
        self.deviceProvider = deviceProvider
        self.positionProvider = positionProvider
    }

    public var snapshot: CameraDeviceSnapshot {
        guard let device = deviceProvider() else {
            return CameraDeviceSnapshot(
                position: positionProvider(),
                zoomFactor: 1,
                lensPosition: nil,
                exposureBias: nil,
                torchActive: false,
                flashAvailable: false,
                torchAvailable: false,
                focusPoint: focusPoint,
                exposurePoint: exposurePoint,
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
            torchActive: device.isTorchActive,
            flashAvailable: device.hasFlash,
            torchAvailable: device.hasTorch,
            focusPoint: focusPoint,
            exposurePoint: exposurePoint,
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
            eventHandler?(.zoomFactorChanged(resolved))
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
            eventHandler?(.zoomFactorChanged(resolved))
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
            eventHandler?(.focusPointChanged(point))
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
            eventHandler?(.exposurePointChanged(point))
        }
    }

    @discardableResult
    public func setExposureBias(_ bias: Float) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "set exposure bias") { device in
            let resolved = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(resolved)
            eventHandler?(.exposureBiasChanged(resolved))
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
            eventHandler?(.torchActiveChanged(isActive))
        }
    }

    @discardableResult
    public func setPreferredFlashMode(_ flashMode: AVCaptureDevice.FlashMode) -> CameraDeviceSnapshot {
        preferredFlashMode = flashMode
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
            eventHandler?(.frameRateChanged(range))
        }
    }

    @discardableResult
    public func selectFormat(where matches: (AVCaptureDevice.Format) -> Bool) throws -> CameraDeviceSnapshot {
        return try withLockedDevice(operation: "select device format") { device in
            guard let format = device.formats.first(where: matches) else {
                throw CameraDeviceControlError.unsupportedControl("matching format")
            }
            device.activeFormat = format
            eventHandler?(.formatChanged("\(format.formatDescription)"))
        }
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
