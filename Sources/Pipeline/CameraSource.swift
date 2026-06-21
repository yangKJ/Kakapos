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

    private let queue = DispatchQueue(label: "com.condy.kakapos.camera-source")
    private var frameIndex: Int64 = 0
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    public init(sessionPreset: AVCaptureSession.Preset = .high, position: AVCaptureDevice.Position = .back) throws {
        self.session = AVCaptureSession()
        super.init()
        try configure(sessionPreset: sessionPreset, position: position)
    }

    public func start() {
        queue.async { self.session.startRunning() }
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
        if session.canAddInput(videoInput) { session.addInput(videoInput) }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let audioDevice = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
            session.addInput(audioInput)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
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
