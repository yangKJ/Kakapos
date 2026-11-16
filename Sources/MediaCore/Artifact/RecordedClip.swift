//
//  RecordedClip.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import AVFoundation
import Foundation

public let RecordedClipFilenameKey = "RecordedClipFilenameKey"
public let RecordedClipInfoDictionaryKey = "RecordedClipInfoDictionaryKey"

public enum RecordedClipMetadataKey {
    public static let identifier = "kakapos.asset.recorded-clip.identifier"
    public static let segmentCount = "kakapos.asset.recorded-clip.segment-count"
    public static let containsVideo = "kakapos.asset.recorded-clip.contains-video"
    public static let containsAudio = "kakapos.asset.recorded-clip.contains-audio"
    public static let mutedOnMerge = "kakapos.asset.recorded-clip.muted-on-merge"
}

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
        var userInfo: [String: Any] = sessionManifest.reduce(into: [:]) { result, element in
            result[element.key] = element.value
        }
        userInfo.merge([
            RecordedClipMetadataKey.segmentCount: segmentCount,
            RecordedClipMetadataKey.containsVideo: containsVideo,
            RecordedClipMetadataKey.containsAudio: containsAudio,
            RecordedClipMetadataKey.mutedOnMerge: isMutedOnMerge
        ]) { current, _ in current }
        return userInfo
    }
}

/// 成功写入时钟的有界摘要；帧率允许可变，暂停由录制器先规范化时间。
public struct RecordingCadence: Codable, Equatable, Sendable {
    public private(set) var videoFrameCount = 0
    public private(set) var audioSampleBufferCount = 0
    public private(set) var droppedVideoFrames = 0
    public private(set) var droppedAudioBuffers = 0
    public private(set) var nonMonotonicVideoFrames = 0
    public private(set) var maximumVideoGapSeconds = 0.0
    private var firstVideo: Double?
    private var lastVideo: Double?
    private var videoEnd: Double?
    private var firstAudio: Double?
    private var audioEnd: Double?

    public init() {}

    public var effectiveVideoFrameRate: Double? {
        guard videoFrameCount > 1, let firstVideo, let lastVideo, lastVideo > firstVideo else { return nil }
        return Double(videoFrameCount - 1) / (lastVideo - firstVideo)
    }
    public var audioVideoStartOffsetSeconds: Double? {
        guard let firstAudio, let firstVideo else { return nil }
        return firstAudio - firstVideo
    }
    public var audioVideoEndOffsetSeconds: Double? {
        guard let audioEnd, let videoEnd else { return nil }
        return audioEnd - videoEnd
    }

    public mutating func recordVideo(seconds: Double, duration: Double) {
        guard seconds.isFinite else { return }
        if let lastVideo {
            if seconds <= lastVideo { nonMonotonicVideoFrames += 1 }
            maximumVideoGapSeconds = max(maximumVideoGapSeconds, seconds - lastVideo)
        }
        videoFrameCount += 1
        firstVideo = firstVideo ?? seconds
        lastVideo = max(lastVideo ?? seconds, seconds)
        // 未知末帧时长不能伪装成0，否则会制造一个假的音画尾部偏移。
        let end = seconds + duration
        videoEnd = duration.isFinite && duration > 0 && end.isFinite ? max(videoEnd ?? end, end) : nil
    }

    public mutating func recordAudio(seconds: Double, duration: Double) {
        guard seconds.isFinite else { return }
        audioSampleBufferCount += 1
        firstAudio = firstAudio ?? seconds
        let end = seconds + duration
        audioEnd = duration.isFinite && duration > 0 && end.isFinite ? max(audioEnd ?? end, end) : nil
    }

    public mutating func recordDrop(audio: Bool) {
        if audio { droppedAudioBuffers += 1 } else { droppedVideoFrames += 1 }
    }
}

public final class RecordedClip {
    public let recordingCadence: RecordingCadence?
    public let identifier: UUID
    public let outputURL: URL?
    public let duration: CMTime
    public let startedAt: CMTime?
    public let endedAt: CMTime?
    public let segments: [RecordedClipSegment]
    public let isMutedOnMerge: Bool
    public let infoDictionary: [String: Any]?
    public let thumbnailTime: CMTime?
    public let sessionManifest: [String: Any]?

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
        sessionManifest: [String: Any]? = nil,
        recordingCadence: RecordingCadence? = nil
    ) {
        self.recordingCadence = recordingCadence
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
        guard
            let representationDictionary,
            let filename = representationDictionary[RecordedClipFilenameKey] as? String
        else {
            self.init(outputURL: nil, duration: .zero, startedAt: nil, endedAt: nil)
            return
        }
        self.init(
            outputURL: Self.outputURL(filename: filename, directoryPath: directoryPath),
            duration: .zero,
            startedAt: nil,
            endedAt: nil,
            infoDictionary: representationDictionary[RecordedClipInfoDictionaryKey] as? [String: Any]
        )
    }

    public static func outputURL(filename: String, directoryPath: String) -> URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent(filename)
    }

}

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
