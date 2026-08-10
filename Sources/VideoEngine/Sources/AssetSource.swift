//
//  AssetSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import KakaposMediaCore
import AVFoundation

public final class AssetSource: MediaSource {
    public enum State: Equatable {
        case idle
        case reading
        case paused
        case finished
        case cancelled
        case failed
    }

    public enum MetadataKey {
        public static let mediaType = "kakapos.asset.media-type"
        public static let sourceTrackID = "kakapos.asset.track-id"
        public static let sourceURL = "kakapos.asset.url"
        public static let recordedClipIdentifier = RecordedClipMetadataKey.identifier
        public static let recordedClipSegmentCount = RecordedClipMetadataKey.segmentCount
        public static let recordedClipContainsVideo = RecordedClipMetadataKey.containsVideo
        public static let recordedClipContainsAudio = RecordedClipMetadataKey.containsAudio
        public static let recordedClipMutedOnMerge = RecordedClipMetadataKey.mutedOnMerge
    }

    public weak var delegate: MediaSourceDelegate?
    public let asset: AVAsset
    public let timeRange: CMTimeRange?
    public let videoOutputSettings: [String: Any]
    public let audioOutputSettings: [String: Any]?
    public let callbackQueue: DispatchQueue
    public let frameUserInfo: [String: Any]

    public var state: State {
        pauseCondition.lock()
        let value = _state
        pauseCondition.unlock()
        return value
    }

    private let queue = DispatchQueue(label: "com.condy.kakapos.asset-source")
    private let deliveryQueue: DispatchQueue
    private let deliveryFence = NSRecursiveLock()
    private let pauseCondition = NSCondition()
    private var _state: State = .idle
    private var reader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var audioOutput: AVAssetReaderTrackOutput?
    private var isCancelled = false
    private var shouldStop = false
    private var frameIndex: Int64 = 0
    private var pendingVideoBuffer: CMSampleBuffer?
    private var pendingAudioBuffer: CMSampleBuffer?
    private var generation: UInt64 = 0
    private var didScheduleTerminalCallback = false

    public init(
        asset: AVAsset,
        timeRange: CMTimeRange? = nil,
        videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ],
        audioOutputSettings: [String: Any]? = nil,
        frameUserInfo: [String: Any] = [:],
        callbackQueue: DispatchQueue = .main
    ) {
        self.asset = asset
        self.timeRange = timeRange
        self.videoOutputSettings = videoOutputSettings
        self.audioOutputSettings = audioOutputSettings
        self.frameUserInfo = frameUserInfo
        self.callbackQueue = callbackQueue
        deliveryQueue = DispatchQueue(
            label: "com.condy.kakapos.asset-source.delivery",
            target: callbackQueue
        )
    }

    public convenience init?(
        recordedClip: RecordedClip,
        timeRange: CMTimeRange? = nil,
        videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ],
        audioOutputSettings: [String: Any]? = nil,
        callbackQueue: DispatchQueue = .main
    ) {
        guard let asset = recordedClip.asset else {
            return nil
        }
        self.init(
            asset: asset,
            timeRange: timeRange,
            videoOutputSettings: videoOutputSettings,
            audioOutputSettings: audioOutputSettings,
            frameUserInfo: Self.makeRecordedClipUserInfo(recordedClip),
            callbackQueue: callbackQueue
        )
    }

    public func start() {
        pauseCondition.lock()
        guard _state == .idle, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        generation &+= 1
        let runGeneration = generation
        _state = .reading
        pauseCondition.unlock()

        queue.async {
            do {
                guard try self.configureReaderIfNeeded(for: runGeneration) else { return }
                guard try self.startReaderIfActive(for: runGeneration) != nil else { return }
                self.readFrames(for: runGeneration)
            } catch {
                self.finish(with: error, expectedGeneration: runGeneration)
            }
        }
    }

    public func pause() {
        pauseCondition.lock()
        defer { pauseCondition.unlock() }
        guard _state == .reading else { return }
        _state = .paused
    }

    public func resume() {
        pauseCondition.lock()
        defer {
            pauseCondition.broadcast()
            pauseCondition.unlock()
        }
        guard _state == .paused else { return }
        _state = .reading
    }

    public func stop() {
        terminate(as: .finished, cancelled: false)
    }

    public func cancel() {
        terminate(as: .cancelled, cancelled: true)
    }

    private func configureReaderIfNeeded(for expectedGeneration: UInt64) throws -> Bool {
        pauseCondition.lock()
        let alreadyConfigured = reader != nil
        let canConfigure = isActiveRun(expectedGeneration)
        pauseCondition.unlock()
        guard canConfigure else { return false }
        guard alreadyConfigured == false else { return true }

        let reader = try AVAssetReader(asset: asset)
        var configuredVideoOutput: AVAssetReaderTrackOutput?
        var configuredAudioOutput: AVAssetReaderTrackOutput?
        if let timeRange {
            reader.timeRange = timeRange
        }

        if let track = asset.tracks(withMediaType: .video).first {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: videoOutputSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw VideoX.Error.videoTrackEmpty
            }
            reader.add(output)
            configuredVideoOutput = output
        }

        if let track = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: audioOutputSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw VideoX.Error.unknown
            }
            reader.add(output)
            configuredAudioOutput = output
        }

        pauseCondition.lock()
        guard isActiveRun(expectedGeneration) else {
            pauseCondition.unlock()
            reader.cancelReading()
            return false
        }
        self.reader = reader
        videoOutput = configuredVideoOutput
        audioOutput = configuredAudioOutput
        pauseCondition.unlock()
        return true
    }

    private func startReaderIfActive(for expectedGeneration: UInt64) throws -> AVAssetReader? {
        pauseCondition.lock()
        guard isActiveRun(expectedGeneration), let reader else {
            pauseCondition.unlock()
            return nil
        }
        let didStart = reader.startReading()
        let error = reader.error
        pauseCondition.unlock()
        guard didStart else {
            throw error ?? VideoX.Error.unknown
        }
        return reader
    }

    private func readFrames(for expectedGeneration: UInt64) {
        while waitUntilReady(for: expectedGeneration) {

            if pendingVideoBuffer == nil {
                pendingVideoBuffer = videoOutput?.copyNextSampleBuffer()
            }
            if pendingAudioBuffer == nil {
                pendingAudioBuffer = audioOutput?.copyNextSampleBuffer()
            }

            switch nextReadableBuffer(video: pendingVideoBuffer, audio: pendingAudioBuffer) {
            case .video(let sampleBuffer):
                pendingVideoBuffer = nil
                dispatch(sampleBuffer: sampleBuffer, mediaType: .video, generation: expectedGeneration)
            case .audio(let sampleBuffer):
                pendingAudioBuffer = nil
                dispatch(sampleBuffer: sampleBuffer, mediaType: .audio, generation: expectedGeneration)
            case .none:
                completeReading(expectedGeneration: expectedGeneration)
                return
            }
        }
    }

    private enum ReadableBuffer {
        case video(CMSampleBuffer)
        case audio(CMSampleBuffer)
        case none
    }

    private func nextReadableBuffer(video: CMSampleBuffer?, audio: CMSampleBuffer?) -> ReadableBuffer {
        switch (video, audio) {
        case let (video?, audio?):
            let videoTime = CMSampleBufferGetPresentationTimeStamp(video)
            let audioTime = CMSampleBufferGetPresentationTimeStamp(audio)
            if videoTime <= audioTime {
                return .video(video)
            }
            return .audio(audio)
        case let (video?, nil):
            return .video(video)
        case let (nil, audio?):
            return .audio(audio)
        case (nil, nil):
            return .none
        }
    }

    private func dispatch(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType, generation: UInt64) {
        frameIndex += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let metadata = FrameMetadata(
            presentationTime: presentationTime,
            duration: CMSampleBufferGetDuration(sampleBuffer).isValid ? CMSampleBufferGetDuration(sampleBuffer) : nil,
            sourceTime: presentationTime,
            trackTransform: trackTransform(for: mediaType),
            frameIndex: frameIndex,
            userInfo: frameUserInfo.merging([
                MetadataKey.mediaType: mediaType.rawValue,
                MetadataKey.sourceTrackID: sourceTrackID(for: mediaType) as Any,
                MetadataKey.sourceURL: (asset as? AVURLAsset)?.url as Any
            ]) { _, new in new }
        )
        let frame = SampleBufferFrame(sampleBuffer: sampleBuffer, metadata: metadata)
        deliveryQueue.async {
            self.deliveryFence.lock()
            defer { self.deliveryFence.unlock() }
            guard self.canDeliverFrame(for: generation) else { return }
            self.delegate?.mediaSource(self, didOutput: frame)
        }
    }

    private func sourceTrackID(for mediaType: AVMediaType) -> CMPersistentTrackID? {
        asset.tracks(withMediaType: mediaType).first?.trackID
    }

    private func trackTransform(for mediaType: AVMediaType) -> CGAffineTransform {
        asset.tracks(withMediaType: mediaType).first?.preferredTransform ?? .identity
    }

    private func completeReading(expectedGeneration: UInt64) {
        guard let reader else {
            finish(with: VideoX.Error.unknown, expectedGeneration: expectedGeneration)
            return
        }

        switch reader.status {
        case .completed, .reading, .unknown:
            completeNaturally(expectedGeneration: expectedGeneration)
        case .cancelled:
            terminate(as: .cancelled, cancelled: true)
        case .failed:
            finish(with: reader.error ?? VideoX.Error.unknown, expectedGeneration: expectedGeneration)
        @unknown default:
            finish(with: reader.error ?? VideoX.Error.unknown, expectedGeneration: expectedGeneration)
        }
    }

    private func finish(with error: Error, expectedGeneration: UInt64) {
        pauseCondition.lock()
        guard generation == expectedGeneration, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        generation &+= 1
        _state = isCancelled ? .cancelled : .failed
        didScheduleTerminalCallback = true
        pauseCondition.broadcast()
        pauseCondition.unlock()
        deliveryQueue.async {
            self.delegate?.mediaSource(self, didFail: error)
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private func waitUntilReady(for expectedGeneration: UInt64) -> Bool {
        pauseCondition.lock()
        while _state == .paused && generation == expectedGeneration && !shouldStop && !isCancelled {
            pauseCondition.wait()
        }
        let isReady = isActiveRun(expectedGeneration)
        pauseCondition.unlock()
        return isReady
    }

    private func isActiveRun(_ expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration
            && (_state == .reading || _state == .paused)
            && shouldStop == false
            && isCancelled == false
            && didScheduleTerminalCallback == false
    }

    private func canDeliverFrame(for expectedGeneration: UInt64) -> Bool {
        pauseCondition.lock()
        let canDeliver = generation == expectedGeneration
        pauseCondition.unlock()
        return canDeliver
    }

    private func terminate(as terminalState: State, cancelled: Bool) {
        pauseCondition.lock()
        guard didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        isCancelled = cancelled
        generation &+= 1
        _state = terminalState
        didScheduleTerminalCallback = true
        let reader = self.reader
        pauseCondition.broadcast()
        pauseCondition.unlock()

        deliveryFence.lock()
        deliveryFence.unlock()
        queue.async {
            reader?.cancelReading()
            self.deliveryQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
            }
        }
    }

    private func completeNaturally(expectedGeneration: UInt64) {
        pauseCondition.lock()
        guard generation == expectedGeneration, didScheduleTerminalCallback == false else {
            pauseCondition.unlock()
            return
        }
        shouldStop = true
        _state = .finished
        didScheduleTerminalCallback = true
        pauseCondition.broadcast()
        pauseCondition.unlock()
        deliveryQueue.async {
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private static func makeRecordedClipUserInfo(_ recordedClip: RecordedClip) -> [String: Any] {
        var userInfo: [String: Any] = recordedClip.mergeHandoff.metadataUserInfo
        userInfo[MetadataKey.recordedClipIdentifier] = recordedClip.identifier.uuidString
        return userInfo
    }
}
