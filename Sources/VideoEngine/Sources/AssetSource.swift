//
//  AssetSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
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
        public static let recordedClipIdentifier = "kakapos.asset.recorded-clip.identifier"
        public static let recordedClipSegmentCount = "kakapos.asset.recorded-clip.segment-count"
        public static let recordedClipContainsVideo = "kakapos.asset.recorded-clip.contains-video"
        public static let recordedClipContainsAudio = "kakapos.asset.recorded-clip.contains-audio"
        public static let recordedClipMutedOnMerge = "kakapos.asset.recorded-clip.muted-on-merge"
    }

    public weak var delegate: MediaSourceDelegate?
    public let asset: AVAsset
    public let timeRange: CMTimeRange?
    public let videoOutputSettings: [String: Any]
    public let audioOutputSettings: [String: Any]?
    public let callbackQueue: DispatchQueue
    public let frameUserInfo: [String: Any]

    public private(set) var state: State = .idle

    private let queue = DispatchQueue(label: "com.condy.kakapos.asset-source")
    private let pauseCondition = NSCondition()
    private var reader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var audioOutput: AVAssetReaderTrackOutput?
    private var isCancelled = false
    private var shouldStop = false
    private var frameIndex: Int64 = 0
    private var pendingVideoBuffer: CMSampleBuffer?
    private var pendingAudioBuffer: CMSampleBuffer?

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
        queue.async {
            guard self.state == .idle else { return }
            do {
                try self.configureReaderIfNeeded()
                guard let reader = self.reader else { return }
                guard reader.startReading() else {
                    throw reader.error ?? VideoX.Error.unknown
                }
                self.state = .reading
                self.readFrames()
            } catch {
                self.finish(with: error)
            }
        }
    }

    public func pause() {
        pauseCondition.lock()
        defer { pauseCondition.unlock() }
        guard state == .reading else { return }
        state = .paused
    }

    public func resume() {
        pauseCondition.lock()
        defer {
            pauseCondition.broadcast()
            pauseCondition.unlock()
        }
        guard state == .paused else { return }
        state = .reading
    }

    public func stop() {
        queue.async {
            self.shouldStop = true
            self.resume()
        }
    }

    public func cancel() {
        queue.async {
            guard self.state != .cancelled && self.state != .finished else { return }
            self.isCancelled = true
            self.reader?.cancelReading()
            self.state = .cancelled
            self.resume()
            self.callbackQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
            }
        }
    }

    private func configureReaderIfNeeded() throws {
        guard reader == nil else { return }

        let reader = try AVAssetReader(asset: asset)
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
            videoOutput = output
        }

        if let track = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: audioOutputSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw VideoX.Error.unknown
            }
            reader.add(output)
            audioOutput = output
        }

        self.reader = reader
    }

    private func readFrames() {
        while !shouldStop && !isCancelled {
            waitIfNeeded()
            if shouldStop || isCancelled {
                break
            }

            if pendingVideoBuffer == nil {
                pendingVideoBuffer = videoOutput?.copyNextSampleBuffer()
            }
            if pendingAudioBuffer == nil {
                pendingAudioBuffer = audioOutput?.copyNextSampleBuffer()
            }

            switch nextReadableBuffer(video: pendingVideoBuffer, audio: pendingAudioBuffer) {
            case .video(let sampleBuffer):
                pendingVideoBuffer = nil
                dispatch(sampleBuffer: sampleBuffer, mediaType: .video)
            case .audio(let sampleBuffer):
                pendingAudioBuffer = nil
                dispatch(sampleBuffer: sampleBuffer, mediaType: .audio)
            case .none:
                completeReading()
                return
            }
        }

        if shouldStop && state != .finished {
            state = .finished
            callbackQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
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

    private func dispatch(sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
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
        let frame = MediaFrame(sampleBuffer: sampleBuffer, metadata: metadata)
        callbackQueue.async {
            self.delegate?.mediaSource(self, didOutput: frame)
        }
    }

    private func sourceTrackID(for mediaType: AVMediaType) -> CMPersistentTrackID? {
        asset.tracks(withMediaType: mediaType).first?.trackID
    }

    private func trackTransform(for mediaType: AVMediaType) -> CGAffineTransform {
        asset.tracks(withMediaType: mediaType).first?.preferredTransform ?? .identity
    }

    private func completeReading() {
        guard let reader else {
            finish(with: VideoX.Error.unknown)
            return
        }

        switch reader.status {
        case .completed, .reading, .unknown:
            state = .finished
            callbackQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
            }
        case .cancelled:
            state = .cancelled
            callbackQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
            }
        case .failed:
            finish(with: reader.error ?? VideoX.Error.unknown)
        @unknown default:
            finish(with: reader.error ?? VideoX.Error.unknown)
        }
    }

    private func finish(with error: Error) {
        state = isCancelled ? .cancelled : .failed
        callbackQueue.async {
            self.delegate?.mediaSource(self, didFail: error)
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private func waitIfNeeded() {
        pauseCondition.lock()
        while state == .paused && !shouldStop && !isCancelled {
            pauseCondition.wait()
        }
        pauseCondition.unlock()
    }

    private static func makeRecordedClipUserInfo(_ recordedClip: RecordedClip) -> [String: Any] {
        var userInfo: [String: Any] = recordedClip.mergeHandoff.metadataUserInfo
        userInfo[MetadataKey.recordedClipIdentifier] = recordedClip.identifier.uuidString
        return userInfo
    }
}
