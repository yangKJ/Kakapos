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
    public enum MetadataKey {
        public static let mediaType = "kakapos.camera.media-type"
        public static let cameraPosition = "kakapos.camera.position"
        public static let sessionState = "kakapos.camera.session-state"
    }

    public weak var delegate: MediaSourceDelegate?
    public var session: AVCaptureSession { realtime.captureSession ?? fallbackSession }
    public var previewLayer: AVCaptureVideoPreviewLayer { realtime.previewLayer }
    public private(set) var isPaused: Bool = false
    public private(set) var state: CameraSessionState = .idle
    public private(set) var currentPosition: CameraPosition
    public var sessionEventHandler: ((CameraSessionEvent) -> Void)?

    private let queue = DispatchQueue(label: "com.condy.kakapos.camera-source")
    private let realtime: KakaposRealtime
    private let fallbackSession = AVCaptureSession()
    private var lifecycle: CameraSessionLifecycle
    private var frameIndex: Int64 = 0

    public init(sessionPreset: AVCaptureSession.Preset = .high, position: AVCaptureDevice.Position = .back) throws {
        self.realtime = KakaposRealtime()
        self.currentPosition = Self.cameraPosition(from: position)
        self.lifecycle = CameraSessionLifecycle(position: Self.cameraPosition(from: position))
        super.init()
        configure(position: position, sessionPreset: sessionPreset)
    }

    public func start() {
        publish(.startRequested)
        queue.async {
            do {
                try self.realtime.start()
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
    }

    public func resume() {
        isPaused = false
    }

    public func stop() {
        queue.async {
            self.realtime.stop()
        }
    }

    public func cancel() {
        stop()
    }

    @discardableResult
    public func switchCameraPosition() -> Bool {
        realtime.flipCaptureDevicePosition()
        let nextPosition: CameraPosition = currentPosition == .back ? .front : .back
        publish(.positionChanged(nextPosition))
        return true
    }

    private func configure(position: AVCaptureDevice.Position, sessionPreset: AVCaptureSession.Preset) {
        realtime.delegate = self
        realtime.videoDelegate = self
        realtime.captureMode = .video
        realtime.devicePosition = position
        realtime.previewLayer.videoGravity = .resizeAspectFill
        realtime.videoConfiguration.preset = sessionPreset
        realtime.rawVideoSampleBufferHandler = { [weak self] sampleBuffer, _ in
            self?.emit(sampleBuffer: sampleBuffer, mediaType: .video)
        }
        realtime.rawAudioSampleBufferHandler = { [weak self] sampleBuffer, _ in
            self?.emit(sampleBuffer: sampleBuffer, mediaType: .audio)
        }
    }

    private func emit(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        guard !isPaused else { return }
        frameIndex += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
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
                    MetadataKey.sessionState: String(describing: state)
                ]
            )
        )
        frame.metadata.frameIndex = frameIndex
        DispatchQueue.main.async {
            self.delegate?.mediaSource(self, didOutput: frame)
        }
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

extension CameraSource: KakaposRealtimeDelegate {
    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoConfiguration videoConfiguration: KakaposRealtimeVideoConfiguration) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateAudioConfiguration audioConfiguration: KakaposRealtimeAudioConfiguration) {}

    public func kakaposRealtimeSessionWillStart(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeSessionDidStart(_ kakaposRealtime: KakaposRealtime) {
        publish(.didStartRunning)
    }

    public func kakaposRealtimeSessionDidStop(_ kakaposRealtime: KakaposRealtime) {
        publish(.didStopRunning)
        delegate?.mediaSourceDidFinish(self)
    }

    public func kakaposRealtimeSessionWasInterrupted(_ kakaposRealtime: KakaposRealtime) {
        publish(.wasInterrupted)
    }

    public func kakaposRealtimeSessionInterruptionEnded(_ kakaposRealtime: KakaposRealtime) {
        publish(.interruptionEnded)
    }

    public func kakaposRealtimeCaptureModeWillChange(_ kakaposRealtime: KakaposRealtime) {}

    public func kakaposRealtimeCaptureModeDidChange(_ kakaposRealtime: KakaposRealtime) {}
}

extension CameraSource: KakaposRealtimeVideoDelegate {
    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoZoomFactor videoZoomFactor: Float) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessRawVideoSampleBuffer sampleBuffer: CMSampleBuffer, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessFrame frame: AnyObject, timestamp: TimeInterval, onQueue queue: DispatchQueue) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupVideoInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupAudioInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didStartClipInSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteClip clip: KakaposRealtimeClip, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteSession session: KakaposRealtimeSession) {}

    public func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompletePhotoCaptureFromVideoFrame photoDict: [String : Any]?) {}
}
#endif
