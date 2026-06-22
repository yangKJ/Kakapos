//
//  CameraRecordingController.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class CameraRecordingController {
    public let source: MediaSource
    public let recorderSink: RecorderSink
    public let pipeline: RecordingPipeline
    public var eventHandler: ((CameraRecordingEvent) -> Void)?
    public var stateChangedHandler: ((RecorderSink.State) -> Void)?
    public var durationChangedHandler: ((CMTime) -> Void)?
    public var finishHandler: ((Result<RecordedClip, Error>) -> Void)?

    private let eventDispatcher = CameraEventDispatcher<CameraRecordingEvent>()

    public var state: RecorderSink.State {
        recorderSink.state
    }

    public var snapshot: RecordingPipeline.Snapshot {
        pipeline.snapshot
    }

    public var summary: RecordingPipeline.Summary {
        pipeline.summary
    }

    public var summaryText: String {
        pipeline.summaryText
    }

    public var outputURL: URL {
        recorderSink.outputURL
    }

    public var recordedClip: RecordedClip? {
        recorderSink.recordedClip
    }

    public var isRecordingActive: Bool {
        state == .recording || state == .paused
    }

    public init(
        source: MediaSource,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws {
        self.source = source
        self.pipeline = try RecordingPipeline(
            source: source,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
        self.recorderSink = pipeline.recorderSink
        wireEvents()
    }

#if canImport(UIKit) && !os(watchOS)
    public convenience init(
        configuration: CameraSourceConfiguration = .init(),
        outputURL: URL,
        fileType: AVFileType = .mp4,
        processors: [FrameProcessor] = []
    ) throws {
        let pipeline = try RecordingPipeline(
            configuration: configuration,
            outputURL: outputURL,
            fileType: fileType,
            processors: processors
        )
        self.init(existingPipeline: pipeline)
    }
#endif

    init(existingPipeline: RecordingPipeline) {
        self.source = existingPipeline.source
        self.pipeline = existingPipeline
        self.recorderSink = existingPipeline.recorderSink
        wireEvents()
    }

    @discardableResult
    public func addEventObserver(_ handler: @escaping (CameraRecordingEvent) -> Void) -> UUID {
        eventDispatcher.addObserver(handler)
    }

    public func removeEventObserver(_ token: UUID) {
        eventDispatcher.removeObserver(token)
    }

    public func start() {
        emit(.willStart)
        pipeline.start()
        emit(.didStart)
    }

    public func pause() {
        recorderSink.pauseRecording()
        emit(.didPause)
    }

    public func resume() {
        recorderSink.resumeRecording()
        emit(.didResume)
    }

    public func stop() {
        pipeline.stop()
    }

    public func stopRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        recorderSink.finishRecording { [weak self] result in
            self?.pipeline.stop()
            if case .success(let clip) = result {
                clip.segments.last.map { self?.emit(.clipCompleted($0)) }
            } else if case .failure(let error) = result {
                self?.emit(.didFail(error.localizedDescription))
            }
            self?.finishHandler?(result)
            completion(result)
        }
    }

    public func cancel() {
        pipeline.cancel()
        emit(.didCancel)
    }

    public func finishRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        recorderSink.finishRecording { [weak self] result in
            if case .success(let clip) = result {
                self?.emit(.clipCountChanged(clip.segments.count))
            }
            self?.finishHandler?(result)
            completion(result)
        }
    }

    private func wireEvents() {
        recorderSink.durationChangedHandler = { [weak self] duration in
            self?.durationChangedHandler?(duration)
            self?.emit(.durationChanged(duration))
        }
        recorderSink.droppedFrameHandler = { [weak self] metadata in
            self?.emit(.droppedFrame(metadata))
        }
        recorderSink.runtimeErrorHandler = { [weak self] error in
            self?.emit(.didFail(error.localizedDescription))
        }
        recorderSink.stateChangedHandler = { [weak self] state in
            self?.stateChangedHandler?(state)
            switch state {
            case .preparing:
                self?.emit(.willStart)
            case .recording:
                self?.emit(.didStart)
            case .paused:
                self?.emit(.didPause)
            case .finishing:
                self?.emit(.didFinish)
            case .finished:
                self?.emit(.didFinish)
            case .cancelled:
                self?.emit(.didCancel)
            case .failed:
                self?.emit(.didFail("recorder failed"))
            case .idle:
                break
            }
        }
    }

    private func emit(_ event: CameraRecordingEvent) {
        eventHandler?(event)
        eventDispatcher.emit(event)
    }
}
