//
//  CameraZoomController.swift
//  KakaposCamera
//
//  Created by Condy on 2026/11/9.
//

import AVFoundation
import Foundation

#if canImport(UIKit) && !os(watchOS)
/// 所有设备操作、观察交接和系统控件均由相机会话队列承接。
final class CameraZoomController: NSObject, @unchecked Sendable {
    let queue: DispatchQueue
    private weak var session: AVCaptureSession?
    let device: () -> AVCaptureDevice?
    let controls: CameraDeviceController
    let gate: CameraZoomRequestGate
    var onApplied: (@Sendable (CGFloat, Bool, Bool) -> Void)?
    private var observation: NSKeyValueObservation?
    private var rampObservation: NSKeyValueObservation?
    private var observedDeviceID: String?
    private var lastPublishedAt: TimeInterval = 0
    private var systemControl: AnyObject?
    private var systemRange: ClosedRange<CGFloat>?
    private var systemDeviceID: String?
    private var systemTitle = "Zoom"

    init(
        queue: DispatchQueue,
        session: AVCaptureSession,
        device: @escaping () -> AVCaptureDevice?,
        controls: CameraDeviceController,
        gate: CameraZoomRequestGate
    ) {
        self.queue = queue
        self.session = session
        self.device = device
        self.controls = controls
        self.gate = gate
    }

    func observe() {
        guard let current = device(), current.uniqueID != observedDeviceID else { return }
        observation = nil
        rampObservation = nil
        observedDeviceID = current.uniqueID
        let identity = current.uniqueID
        observation = current.observe(\.videoZoomFactor, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.device()?.uniqueID == identity else { return }
                self.publish(system: self.systemInteractionActive)
            }
        }
        rampObservation = current.observe(\.isRampingVideoZoom, options: [.new]) { [weak self] _, change in
            guard let self, change.newValue == false else { return }
            self.queue.async { [weak self] in
                guard let self, self.device()?.uniqueID == identity else { return }
                self.publish(system: self.systemInteractionActive, force: true, final: true)
            }
        }
    }

    func update(_ factor: CGFloat, rampRate: Float?) throws -> CameraDeviceSnapshot {
        observe()
        systemInteractionActive = false
        let snapshot: CameraDeviceSnapshot
        if let rampRate {
            guard rampRate.isFinite, rampRate > 0 else { throw CameraDeviceControlError.unsupportedControl("invalid zoom rate") }
            snapshot = try controls.rampZoomFactor(to: factor, rate: rampRate)
        } else {
            snapshot = try controls.setZoomFactor(factor)
        }
        publish(system: false, force: true)
        return snapshot
    }

    func freeze() throws -> CameraDeviceSnapshot {
        let snapshot = try controls.stopZoomRamp()
        publish(system: false, force: true, final: true)
        return snapshot
    }

    func invalidate() {
        _ = try? freeze()
        observation = nil
        rampObservation = nil
        observedDeviceID = nil
        configureSystemControl(range: nil)
        onApplied = nil
    }

    func publish(system: Bool, force: Bool = false, final: Bool = false) {
        guard let device = device() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastPublishedAt >= 1.0 / 30 else { return }
        lastPublishedAt = now
        onApplied?(device.videoZoomFactor, system, final)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *), let slider = systemControl as? AVCaptureSlider {
            let value = Float(device.videoZoomFactor)
            if abs(slider.value - value) > 0.001 { slider.value = value }
        }
        #endif
    }

    private var systemInteractionActive = false

    func setSystemInteractionEnabled(_ enabled: Bool) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *), let control = systemControl as? AVCaptureControl {
            control.isEnabled = enabled
        }
        #endif
        if !enabled { systemInteractionActive = false }
    }

    func configureSystemControl(range: ClosedRange<CGFloat>?, title: String = "Zoom") {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            guard let session else { return }
            let identity = device()?.uniqueID
            guard systemRange != range || systemDeviceID != identity || systemTitle != title else { return }
            systemRange = range
            systemTitle = title
            systemDeviceID = identity
            if let owned = systemControl as? AVCaptureControl, session.controls.contains(where: { $0 === owned }) {
                session.removeControl(owned)
            }
            systemControl = nil
            systemInteractionActive = false
            if session.controls.isEmpty, (session.controlsDelegate as AnyObject?) === self {
                session.setControlsDelegate(nil, queue: nil)
            }
            guard let range, let device = device(), session.supportsControls else { return }
            guard session.controlsDelegate == nil || (session.controlsDelegate as AnyObject?) === self else { return }
            let slider = AVCaptureSlider(
                title,
                symbolName: "plus.magnifyingglass",
                in: Float(range.lowerBound)...Float(range.upperBound)
            )
            slider.isEnabled = gate.isEnabled
            slider.value = Float(device.videoZoomFactor)
            slider.prominentValues = [1, 2, 3, 5].filter { range.contains(CGFloat($0)) }.map(Float.init)
            slider.setActionQueue(queue) { [weak self] value in
                guard let self, self.device()?.uniqueID == identity, self.gate.issue() != nil else { return }
                self.systemInteractionActive = true
                _ = try? self.controls.setZoomFactor(CGFloat(value))
                self.publish(system: true, force: true)
            }
            guard session.canAddControl(slider) else { return }
            session.setControlsDelegate(self, queue: queue)
            session.addControl(slider)
            systemControl = slider
        }
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
@available(iOS 18.0, *)
extension CameraZoomController: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) { }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) { }
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) { }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        guard systemInteractionActive else { return }
        systemInteractionActive = false
        publish(system: true, force: true, final: true)
    }
}
#endif
#endif
