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

    public func start() {
        pipeline.start()
        eventHandler?(.didStart)
    }

    public func pause() {
        recorderSink.pauseRecording()
        eventHandler?(.didPause)
    }

    public func resume() {
        recorderSink.resumeRecording()
        eventHandler?(.didResume)
    }

    public func stop() {
        pipeline.stop()
    }

    public func stopRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        recorderSink.finishRecording { [weak self] result in
            self?.pipeline.stop()
            self?.finishHandler?(result)
            completion(result)
        }
    }

    public func cancel() {
        pipeline.cancel()
        eventHandler?(.didCancel)
    }

    public func finishRecording(completion: @escaping (Result<RecordedClip, Error>) -> Void) {
        recorderSink.finishRecording { [weak self] result in
            if case .success(let clip) = result {
                self?.eventHandler?(.clipCountChanged(clip.segments.count))
            }
            self?.finishHandler?(result)
            completion(result)
        }
    }

    private func wireEvents() {
        recorderSink.durationChangedHandler = { [weak self] duration in
            self?.durationChangedHandler?(duration)
            self?.eventHandler?(.durationChanged(duration))
        }
        recorderSink.stateChangedHandler = { [weak self] state in
            self?.stateChangedHandler?(state)
            switch state {
            case .recording:
                self?.eventHandler?(.didStart)
            case .paused:
                self?.eventHandler?(.didPause)
            case .finished:
                self?.eventHandler?(.didFinish)
            case .cancelled:
                self?.eventHandler?(.didCancel)
            case .idle:
                break
            }
        }
    }
}
