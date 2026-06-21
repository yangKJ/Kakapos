//
//  CameraSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

#if canImport(UIKit) && !os(watchOS)
public final class CameraSource: NSObject, MediaSource {
    public weak var delegate: MediaSourceDelegate?
    public let session: AVCaptureSession
    public private(set) var isPaused: Bool = false
    public private(set) var state: CameraSessionState = .idle
    public private(set) var currentPosition: CameraPosition
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?

    private let queue = DispatchQueue(label: "com.condy.kakapos.camera-source")
    private var frameIndex: Int64 = 0
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var lifecycle: CameraSessionLifecycle

    public init(sessionPreset: AVCaptureSession.Preset = .high, position: AVCaptureDevice.Position = .back) throws {
        self.session = AVCaptureSession()
        self.currentPosition = Self.cameraPosition(from: position)
        self.lifecycle = CameraSessionLifecycle(position: Self.cameraPosition(from: position))
        super.init()
        try configure(sessionPreset: sessionPreset, position: position)
        addObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func start() {
        publish(.startRequested)
        queue.async {
            self.session.startRunning()
            self.publish(.didStartRunning)
        }
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }

    public func stop() {
        queue.async {
            self.session.stopRunning()
            self.publish(.didStopRunning)
            DispatchQueue.main.async { self.delegate?.mediaSourceDidFinish(self) }
        }
    }

    public func cancel() {
        stop()
    }

    private func configure(sessionPreset: AVCaptureSession.Preset, position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        session.sessionPreset = sessionPreset
        defer { session.commitConfiguration() }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw VideoX.Error.videoTrackEmpty
        }
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            self.videoInput = videoInput
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let audioDevice = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
            session.addInput(audioInput)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        }
    }

    @discardableResult
    public func switchCameraPosition() -> Bool {
        queue.sync {
            guard let currentInput = videoInput else { return false }
            let nextPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
            guard let nextDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: nextPosition),
                  let nextInput = try? AVCaptureDeviceInput(device: nextDevice) else {
                return false
            }
            session.beginConfiguration()
            session.removeInput(currentInput)
            guard session.canAddInput(nextInput) else {
                session.addInput(currentInput)
                session.commitConfiguration()
                return false
            }
            session.addInput(nextInput)
            session.commitConfiguration()
            videoInput = nextInput
            publish(.positionChanged(Self.cameraPosition(from: nextPosition)))
            return true
        }
    }

    @objc private func handleSessionWasInterrupted(_ notification: Notification) {
        publish(.wasInterrupted)
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        publish(.interruptionEnded)
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        let nsError = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let avError = nsError.flatMap { AVError(_nsError: $0) }
        let isRecoverable = avError?.code == .mediaServicesWereReset
        let description = avError?.localizedDescription ?? nsError?.localizedDescription
        publish(.runtimeError(isRecoverable: isRecoverable, description: description))
        if let avError {
            DispatchQueue.main.async {
                self.delegate?.mediaSource(self, didFail: avError)
            }
        } else if let nsError {
            DispatchQueue.main.async {
                self.delegate?.mediaSource(self, didFail: nsError)
            }
        }
        guard isRecoverable, lifecycle.shouldAttemptRecovery else { return }
        queue.async {
            guard !self.session.isRunning else { return }
            self.publish(.startRequested)
            self.session.startRunning()
            self.publish(.didStartRunning)
        }
    }

    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    private func publish(_ action: CameraLifecycleAction) {
        guard let event = lifecycle.handle(action) else { return }
        state = lifecycle.state
        currentPosition = lifecycle.position
        DispatchQueue.main.async {
            self.sessionEventHandler?(event)
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
}

extension CameraSource: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused else { return }
        frameIndex += 1
        var frame = MediaFrame(sampleBuffer: sampleBuffer)
        frame.metadata.frameIndex = frameIndex
        DispatchQueue.main.async { self.delegate?.mediaSource(self, didOutput: frame) }
    }
}
#endif
