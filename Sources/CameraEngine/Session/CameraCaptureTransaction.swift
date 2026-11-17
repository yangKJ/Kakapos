// 作者：Condy
import AVFoundation
import Foundation

/// 配置失败时撤回新增图节点并恢复原连接；begin/commit 只负责批量应用，不提供回滚。
final class CameraCaptureTransaction {
    private let session: AVCaptureSession
    private let inputs: [AVCaptureInput]
    private let outputs: [AVCaptureOutput]
    private let connections: [AVCaptureConnection]
    private let preset: AVCaptureSession.Preset
    #if canImport(UIKit) && !os(watchOS)
    private let wideColor: Bool
    private let autoAudio: Bool
    private var devices: [ObjectIdentifier: DeviceState] = [:]
    private var photos: [PhotoState] = []
    private struct PhotoState {
        let output: AVCapturePhotoOutput
        let highResolution: Bool
        let live: Bool
        let depth: Bool
        let matte: Bool
        let quality: AVCapturePhotoOutput.QualityPrioritization
        let maximum: CMVideoDimensions?
        let proRAW: Bool?
        init(_ output: AVCapturePhotoOutput) {
            self.output = output; highResolution = output.isHighResolutionCaptureEnabled
            live = output.isLivePhotoCaptureEnabled; depth = output.isDepthDataDeliveryEnabled
            matte = output.isPortraitEffectsMatteDeliveryEnabled; quality = output.maxPhotoQualityPrioritization
            if #available(iOS 16.0, *) { maximum = output.maxPhotoDimensions } else { maximum = nil }
            if #available(iOS 14.3, *) { proRAW = output.isAppleProRAWEnabled } else { proRAW = nil }
        }
        func restore() {
            output.isHighResolutionCaptureEnabled = highResolution
            if output.isLivePhotoCaptureSupported { output.isLivePhotoCaptureEnabled = live }
            if output.isDepthDataDeliverySupported { output.isDepthDataDeliveryEnabled = depth }
            if output.isPortraitEffectsMatteDeliverySupported { output.isPortraitEffectsMatteDeliveryEnabled = matte }
            output.maxPhotoQualityPrioritization = quality
            if #available(iOS 16.0, *), let maximum, maximum.width > 0, maximum.height > 0 { output.maxPhotoDimensions = maximum }
            if #available(iOS 14.3, *), output.isAppleProRAWSupported, let proRAW { output.isAppleProRAWEnabled = proRAW }
        }
    }
    private struct DeviceState {
        let device: AVCaptureDevice
        let format: AVCaptureDevice.Format
        let depthFormat: AVCaptureDevice.Format?
        let color: AVCaptureColorSpace
        let minimum: CMTime
        let maximum: CMTime
        let zoom: CGFloat
        let focus: AVCaptureDevice.FocusMode
        let lens: Float
        let exposure: AVCaptureDevice.ExposureMode
        let duration: CMTime
        let iso: Float
        let bias: Float
        let white: AVCaptureDevice.WhiteBalanceMode
        let gains: AVCaptureDevice.WhiteBalanceGains
        let smooth: Bool
        let subject: Bool
        init(_ device: AVCaptureDevice) {
            self.device = device; format = device.activeFormat; depthFormat = device.activeDepthDataFormat
            color = device.activeColorSpace; minimum = device.activeVideoMinFrameDuration; maximum = device.activeVideoMaxFrameDuration
            zoom = device.videoZoomFactor; focus = device.focusMode; lens = device.lensPosition
            exposure = device.exposureMode; duration = device.exposureDuration; iso = device.iso; bias = device.exposureTargetBias
            white = device.whiteBalanceMode; gains = device.deviceWhiteBalanceGains
            smooth = device.isSmoothAutoFocusEnabled; subject = device.isSubjectAreaChangeMonitoringEnabled
        }
        func restore() throws {
            try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
            if device.activeFormat !== format { device.activeFormat = format }
            if format.supportedColorSpaces.contains(color) { device.activeColorSpace = color }
            if device.activeDepthDataFormat !== depthFormat { device.activeDepthDataFormat = depthFormat }
            device.activeVideoMinFrameDuration = minimum; device.activeVideoMaxFrameDuration = maximum
            device.videoZoomFactor = zoom
            if device.isFocusModeSupported(focus) {
                if focus == .locked, device.isLockingFocusWithCustomLensPositionSupported { device.setFocusModeLocked(lensPosition: lens, completionHandler: nil) }
                else { device.focusMode = focus }
            }
            if device.isExposureModeSupported(exposure) {
                if exposure == .custom { device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil) }
                else { device.exposureMode = exposure }
            }
            device.setExposureTargetBias(bias, completionHandler: nil)
            if device.isWhiteBalanceModeSupported(white) {
                if white == .locked { device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil) }
                else { device.whiteBalanceMode = white }
            }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = smooth }
            device.isSubjectAreaChangeMonitoringEnabled = subject
        }
    }
    #endif
    init(session: AVCaptureSession) {
        self.session = session; inputs = session.inputs; outputs = session.outputs
        connections = session.connections; preset = session.sessionPreset
        #if canImport(UIKit) && !os(watchOS)
        wideColor = session.automaticallyConfiguresCaptureDeviceForWideColor
        autoAudio = session.automaticallyConfiguresApplicationAudioSession
        for input in inputs { if let input = input as? AVCaptureDeviceInput { watch(input.device) } }
        photos = outputs.compactMap { ($0 as? AVCapturePhotoOutput).map(PhotoState.init) }
        #endif
    }
    #if canImport(UIKit) && !os(watchOS)
    func watch(_ device: AVCaptureDevice) {
        guard device.hasMediaType(.video) else { return }
        let key = ObjectIdentifier(device)
        if devices[key] == nil { devices[key] = DeviceState(device) }
    }
    #endif
    func run(_ body: () throws -> Void) throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        do { try body() }
        catch {
            let original = error
            do { try restore() }
            catch { throw Failure(original: original, rollback: error) }
            throw original
        }
    }
    private func restore() throws {
        for connection in session.connections where !connections.contains(where: { $0 === connection }) { session.removeConnection(connection) }
        for output in session.outputs where !outputs.contains(where: { $0 === output }) { session.removeOutput(output) }
        for input in session.inputs where !inputs.contains(where: { $0 === input }) { session.removeInput(input) }
        for input in inputs where !session.inputs.contains(where: { $0 === input }) {
            guard session.canAddInput(input) else { throw CocoaError(.coderInvalidValue) }
            session.addInputWithNoConnections(input)
        }
        for output in outputs where !session.outputs.contains(where: { $0 === output }) {
            guard session.canAddOutput(output) else { throw CocoaError(.coderInvalidValue) }
            session.addOutputWithNoConnections(output)
        }
        for connection in connections where !session.connections.contains(where: { $0 === connection }) {
            guard session.canAddConnection(connection) else { throw CocoaError(.coderInvalidValue) }
            session.addConnection(connection)
        }
        if session.sessionPreset != preset {
            guard session.canSetSessionPreset(preset) else { throw CocoaError(.coderInvalidValue) }
            session.sessionPreset = preset
        }
        #if canImport(UIKit) && !os(watchOS)
        session.automaticallyConfiguresCaptureDeviceForWideColor = wideColor
        session.automaticallyConfiguresApplicationAudioSession = autoAudio
        for state in devices.values { try state.restore() }
        photos.forEach { $0.restore() }
        #endif
    }
    struct Failure: LocalizedError {
        let original: Error
        let rollback: Error
        var errorDescription: String? { "配置失败：\(original.localizedDescription)；恢复失败：\(rollback.localizedDescription)" }
    }
}
