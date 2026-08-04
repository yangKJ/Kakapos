//
//  RecordingSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import KakaposMediaCore

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
