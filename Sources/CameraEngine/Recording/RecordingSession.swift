//
//  RecordingSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public let RecordedClipFilenameKey = "RecordedClipFilenameKey"
public let RecordedClipInfoDictionaryKey = "RecordedClipInfoDictionaryKey"

public struct RecordedClipSegment: Equatable, Sendable {
    public let index: Int
    public let startedAt: CMTime
    public let endedAt: CMTime
    public let duration: CMTime
    public let containsVideo: Bool
    public let containsAudio: Bool

    public init(
        index: Int,
        startedAt: CMTime,
        endedAt: CMTime,
        duration: CMTime,
        containsVideo: Bool,
        containsAudio: Bool
    ) {
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.containsVideo = containsVideo
        self.containsAudio = containsAudio
    }
}

public struct RecordedClipMergeHandoff: Equatable, Sendable {
    public let outputURL: URL?
    public let duration: CMTime
    public let segmentCount: Int
    public let containsVideo: Bool
    public let containsAudio: Bool
    public let thumbnailTime: CMTime?
    public let isMutedOnMerge: Bool
    public let sessionManifest: [String: String]

    public init(
        outputURL: URL?,
        duration: CMTime,
        segmentCount: Int,
        containsVideo: Bool,
        containsAudio: Bool,
        thumbnailTime: CMTime?,
        isMutedOnMerge: Bool,
        sessionManifest: [String: String]
    ) {
        self.outputURL = outputURL
        self.duration = duration
        self.segmentCount = segmentCount
        self.containsVideo = containsVideo
        self.containsAudio = containsAudio
        self.thumbnailTime = thumbnailTime
        self.isMutedOnMerge = isMutedOnMerge
        self.sessionManifest = sessionManifest
    }

    public var summaryText: String {
        "segments \(segmentCount) · duration \(String(format: "%.2fs", duration.seconds)) · video \(containsVideo ? "yes" : "no") · audio \(containsAudio ? "yes" : "no") · mutedOnMerge \(isMutedOnMerge ? "yes" : "no")"
    }

    public var metadataUserInfo: [String: Any] {
        var userInfo: [String: Any] = sessionManifest.reduce(into: [:]) { partialResult, element in
            partialResult[element.key] = element.value
        }
        userInfo.merge([
            AssetSource.MetadataKey.recordedClipSegmentCount: segmentCount,
            AssetSource.MetadataKey.recordedClipContainsVideo: containsVideo,
            AssetSource.MetadataKey.recordedClipContainsAudio: containsAudio,
            AssetSource.MetadataKey.recordedClipMutedOnMerge: isMutedOnMerge
        ]) { current, _ in current }
        return userInfo
    }
}

public final class RecordedClip: @unchecked Sendable {
    public let identifier: UUID
    public var outputURL: URL? {
        didSet {
            cachedAsset = nil
        }
    }
    public let duration: CMTime
    public let startedAt: CMTime?
    public let endedAt: CMTime?
    public let segments: [RecordedClipSegment]
    public var isMutedOnMerge: Bool
    public private(set) var infoDictionary: [String: Any]?
    public let thumbnailTime: CMTime?
    public let sessionManifest: [String: Any]?

    private var cachedAsset: AVAsset?

    public var fileExists: Bool {
        guard let outputURL else { return false }
        return FileManager.default.fileExists(atPath: outputURL.path)
    }

    public var asset: AVAsset? {
        guard let outputURL else { return nil }
        if cachedAsset == nil {
            cachedAsset = AVAsset(url: outputURL)
        }
        return cachedAsset
    }

    public var frameRate: Float {
        guard
            let track = asset?.tracks(withMediaType: .video).first
        else {
            return 0
        }
        return track.nominalFrameRate
    }

    public var containsVideo: Bool {
        segments.contains(where: \.containsVideo)
    }

    public var containsAudio: Bool {
        segments.contains(where: \.containsAudio)
    }

    public var segmentCount: Int {
        segments.count
    }

    public var normalizedSessionManifest: [String: String] {
        var result: [String: String] = [:]
        sessionManifest?.forEach { key, value in
            switch value {
            case let value as String:
                result[key] = value
            case let value as Bool:
                result[key] = value ? "true" : "false"
            case let value as Int:
                result[key] = "\(value)"
            case let value as Double:
                result[key] = String(format: "%.4f", value)
            case let value as CMTime:
                result[key] = String(format: "%.4f", value.seconds)
            default:
                break
            }
        }
        return result
    }

    public var mergeHandoff: RecordedClipMergeHandoff {
        RecordedClipMergeHandoff(
            outputURL: outputURL,
            duration: duration,
            segmentCount: segmentCount,
            containsVideo: containsVideo,
            containsAudio: containsAudio,
            thumbnailTime: thumbnailTime,
            isMutedOnMerge: isMutedOnMerge,
            sessionManifest: normalizedSessionManifest
        )
    }

    public var summaryText: String {
        mergeHandoff.summaryText
    }

    public var representationDictionary: [String: Any]? {
        guard let outputURL else { return nil }
        if let infoDictionary {
            return [
                RecordedClipFilenameKey: outputURL.lastPathComponent,
                RecordedClipInfoDictionaryKey: infoDictionary
            ]
        }
        return [RecordedClipFilenameKey: outputURL.lastPathComponent]
    }

    public init(
        identifier: UUID = UUID(),
        outputURL: URL?,
        duration: CMTime,
        startedAt: CMTime?,
        endedAt: CMTime?,
        segments: [RecordedClipSegment] = [],
        isMutedOnMerge: Bool = false,
        infoDictionary: [String: Any]? = nil,
        thumbnailTime: CMTime? = nil,
        sessionManifest: [String: Any]? = nil
    ) {
        self.identifier = identifier
        self.outputURL = outputURL
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.segments = segments
        self.isMutedOnMerge = isMutedOnMerge
        self.infoDictionary = infoDictionary
        self.thumbnailTime = thumbnailTime
        self.sessionManifest = sessionManifest
    }

    public convenience init(directoryPath: String, representationDictionary: [String: Any]?) {
        if
            let representationDictionary,
            let filename = representationDictionary[RecordedClipFilenameKey] as? String
        {
            let outputURL = Self.outputURL(filename: filename, directoryPath: directoryPath)
            let infoDictionary = representationDictionary[RecordedClipInfoDictionaryKey] as? [String: Any]
            self.init(
                outputURL: outputURL,
                duration: .zero,
                startedAt: nil,
                endedAt: nil,
                segments: [],
                infoDictionary: infoDictionary
            )
        } else {
            self.init(outputURL: nil, duration: .zero, startedAt: nil, endedAt: nil)
        }
    }

    public static func outputURL(filename: String, directoryPath: String) -> URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent(filename)
    }

    public func generatedPreviewImage(at time: CMTime = .zero) -> CGImage? {
        guard let asset else { return nil }
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        do {
            return try imageGenerator.copyCGImage(at: time, actualTime: nil)
        } catch {
            return nil
        }
    }

    public func generatedLastFrameImage() -> CGImage? {
        guard duration.isNumeric, duration > .zero else {
            return generatedPreviewImage()
        }
        return generatedPreviewImage(at: duration)
    }

    public func removeFile() {
        guard let outputURL else { return }
        do {
            try FileManager.default.removeItem(at: outputURL)
            self.outputURL = nil
        } catch {
            return
        }
    }

    public func makeAssetSource(
        timeRange: CMTimeRange? = nil,
        videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ],
        audioOutputSettings: [String: Any]? = nil,
        callbackQueue: DispatchQueue = .main
    ) -> AssetSource? {
        AssetSource(
            recordedClip: self,
            timeRange: timeRange,
            videoOutputSettings: videoOutputSettings,
            audioOutputSettings: audioOutputSettings,
            callbackQueue: callbackQueue
        )
    }

    public func makeTimelinePipeline(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> TimelinePipeline? {
        TimelinePipeline(
            recordedClip: self,
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )
    }

    public func makeExportJob(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> ReaderWriterExportJob? {
        makeTimelinePipeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )?.makeExportJob(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    public func makeExportTask(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> TimelineExportTask? {
        makeTimelinePipeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )?.makeExportTask(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }
}

#if canImport(UIKit) || os(macOS)
public extension RecordedClip {
    func makePlayerItem() -> AVPlayerItem? {
        guard let asset else { return nil }
        return AVPlayerItem(asset: asset)
    }

    func makePlayerFrameSource(
        preferredFramesPerSecond: Int = 30
    ) -> PlayerFrameSource? {
        PlayerFrameSource(recordedClip: self, preferredFramesPerSecond: preferredFramesPerSecond)
    }

    func makePreviewPipeline(
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline? {
        PreviewPipeline(
            recordedClip: self,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }
}
#endif

extension RecordedClip: Equatable {
    public static func == (lhs: RecordedClip, rhs: RecordedClip) -> Bool {
        lhs.identifier == rhs.identifier &&
        lhs.outputURL == rhs.outputURL &&
        lhs.duration == rhs.duration &&
        lhs.startedAt == rhs.startedAt &&
        lhs.endedAt == rhs.endedAt &&
        lhs.segments == rhs.segments &&
        lhs.isMutedOnMerge == rhs.isMutedOnMerge &&
        lhs.thumbnailTime == rhs.thumbnailTime
    }
}

public struct RecordingSessionStateSnapshot: Equatable, Sendable {
    public let currentClipHasStarted: Bool
    public let currentClipHasVideo: Bool
    public let currentClipHasAudio: Bool
    public let clipCount: Int
    public let totalDuration: CMTime
    public let currentClipDuration: CMTime
    public let segmentCount: Int
    public let recordedVideoSegmentCount: Int
    public let recordedAudioSegmentCount: Int
}

final class RecordingSession {
    private let defaultSingleFrameDuration = CMTime(value: 1, timescale: 600)
    private(set) var clips: [RecordedClipSegment] = []
    private(set) var currentClipHasStarted = false
    private(set) var currentClipHasVideo = false
    private(set) var currentClipHasAudio = false
    private(set) var currentClipDuration: CMTime = .zero
    private(set) var totalDuration: CMTime = .zero

    private var currentClipStart: CMTime?
    private var currentClipEnd: CMTime?
    private var currentClipMinimumDuration: CMTime?
    private var nextClipMinimumDuration: CMTime?
    private var timeOffset: CMTime = .zero
    private var pauseAnchor: CMTime?
    private var clipIndex = 0

    func beginClipIfNeeded(at time: CMTime) {
        guard !currentClipHasStarted else { return }
        currentClipHasStarted = true
        currentClipStart = time
        currentClipEnd = time
        currentClipMinimumDuration = nextClipMinimumDuration ?? defaultSingleFrameDuration
        nextClipMinimumDuration = defaultSingleFrameDuration
        currentClipDuration = .zero
        currentClipHasVideo = false
        currentClipHasAudio = false
    }

    func markVideoFrame(at time: CMTime) {
        beginClipIfNeeded(at: time)
        currentClipHasVideo = true
        updateClipTiming(with: time)
    }

    func markAudioFrame(at time: CMTime) {
        beginClipIfNeeded(at: time)
        currentClipHasAudio = true
        updateClipTiming(with: time)
    }

    func pause(at time: CMTime) {
        pauseAnchor = time
    }

    func resume(at time: CMTime) {
        guard let pauseAnchor else { return }
        timeOffset = timeOffset + max(time - pauseAnchor, .zero)
        self.pauseAnchor = nil
    }

    func normalizedTime(for time: CMTime) -> CMTime {
        time - timeOffset
    }

    func configureNextClipMinimumDuration(_ duration: CMTime?) {
        nextClipMinimumDuration = duration
    }

    func finalizeCurrentClipIfNeeded(preferredEndTime: CMTime? = nil) {
        guard currentClipHasStarted,
              let currentClipStart,
              let currentClipEnd else {
            resetCurrentClipFlags()
            return
        }
        var endTime: CMTime
        if let preferredEndTime, preferredEndTime > currentClipStart {
            endTime = preferredEndTime
        } else {
            endTime = currentClipEnd
        }
        var duration = max(endTime - currentClipStart, .zero)
        if duration == .zero, currentClipHasVideo || currentClipHasAudio {
            if let currentClipMinimumDuration, currentClipMinimumDuration > .zero {
                duration = currentClipMinimumDuration
                endTime = currentClipStart + duration
            }
        }
        clips.append(
            RecordedClipSegment(
                index: clipIndex,
                startedAt: currentClipStart,
                endedAt: endTime,
                duration: duration,
                containsVideo: currentClipHasVideo,
                containsAudio: currentClipHasAudio
            )
        )
        totalDuration = clips.reduce(.zero) { $0 + $1.duration }
        clipIndex += 1
        resetCurrentClipFlags()
    }

    func makeRecordedClip(
        outputURL: URL,
        fallbackStartedAt: CMTime?,
        fallbackEndedAt: CMTime?,
        infoDictionary: [String: Any]? = nil
    ) -> RecordedClip {
        let startedAt = clips.first?.startedAt ?? fallbackStartedAt
        let endedAt = clips.last?.endedAt ?? fallbackEndedAt
        let total = clips.reduce(.zero) { $0 + $1.duration }
        let containsVideo = clips.contains(where: \.containsVideo)
        let containsAudio = clips.contains(where: \.containsAudio)
        return RecordedClip(
            outputURL: outputURL,
            duration: total,
            startedAt: startedAt,
            endedAt: endedAt,
            segments: clips,
            infoDictionary: infoDictionary,
            thumbnailTime: startedAt,
            sessionManifest: [
                "clipCount": clips.count,
                "segmentCount": clips.count,
                "videoSegments": clips.filter(\.containsVideo).count,
                "audioSegments": clips.filter(\.containsAudio).count,
                "containsVideo": containsVideo,
                "containsAudio": containsAudio,
                "totalDurationSeconds": total.seconds,
                "startedAtSeconds": startedAt?.seconds ?? 0,
                "endedAtSeconds": endedAt?.seconds ?? 0
            ]
        )
    }

    func trimLastClipEndingIfNeeded(to time: CMTime) {
        guard let last = clips.last, time.isValid, time < last.endedAt else { return }
        let duration = max(time - last.startedAt, .zero)
        let resolvedDuration = duration == .zero ? CMTime(value: 1, timescale: 600) : duration
        clips[clips.count - 1] = RecordedClipSegment(
            index: last.index,
            startedAt: last.startedAt,
            endedAt: last.startedAt + resolvedDuration,
            duration: resolvedDuration,
            containsVideo: last.containsVideo,
            containsAudio: last.containsAudio
        )
        totalDuration = clips.reduce(.zero) { $0 + $1.duration }
    }

    func snapshot() -> RecordingSessionStateSnapshot {
        RecordingSessionStateSnapshot(
            currentClipHasStarted: currentClipHasStarted,
            currentClipHasVideo: currentClipHasVideo,
            currentClipHasAudio: currentClipHasAudio,
            clipCount: clips.count,
            totalDuration: totalDuration,
            currentClipDuration: currentClipDuration,
            segmentCount: clips.count,
            recordedVideoSegmentCount: clips.filter(\.containsVideo).count,
            recordedAudioSegmentCount: clips.filter(\.containsAudio).count
        )
    }

    private func updateClipTiming(with time: CMTime) {
        if let currentClipStart {
            var duration = max(time - currentClipStart, .zero)
            if duration == .zero, let currentClipMinimumDuration, currentClipMinimumDuration > .zero {
                duration = currentClipMinimumDuration
            }
            currentClipDuration = duration
            currentClipEnd = currentClipStart + duration
        } else {
            currentClipEnd = time
        }
    }

    private func resetCurrentClipFlags() {
        currentClipHasStarted = false
        currentClipHasVideo = false
        currentClipHasAudio = false
        currentClipStart = nil
        currentClipEnd = nil
        currentClipMinimumDuration = nil
        currentClipDuration = .zero
    }
}
