//
//  RecordingSession.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public struct RecordedClipSegment: Equatable {
    public let index: Int
    public let startedAt: CMTime
    public let endedAt: CMTime
    public let duration: CMTime

    public init(index: Int, startedAt: CMTime, endedAt: CMTime, duration: CMTime) {
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
    }
}

public struct RecordedClip: Equatable {
    public let outputURL: URL
    public let duration: CMTime
    public let startedAt: CMTime?
    public let endedAt: CMTime?
    public let segments: [RecordedClipSegment]

    public init(
        outputURL: URL,
        duration: CMTime,
        startedAt: CMTime?,
        endedAt: CMTime?,
        segments: [RecordedClipSegment] = []
    ) {
        self.outputURL = outputURL
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.segments = segments
    }
}

public struct RecordingSessionStateSnapshot: Equatable {
    public let currentClipHasStarted: Bool
    public let currentClipHasVideo: Bool
    public let currentClipHasAudio: Bool
    public let clipCount: Int
    public let totalDuration: CMTime
    public let currentClipDuration: CMTime
}

final class RecordingSession {
    private(set) var clips: [RecordedClipSegment] = []
    private(set) var currentClipHasStarted = false
    private(set) var currentClipHasVideo = false
    private(set) var currentClipHasAudio = false
    private(set) var currentClipDuration: CMTime = .zero
    private(set) var totalDuration: CMTime = .zero

    private var currentClipStart: CMTime?
    private var currentClipEnd: CMTime?
    private var timeOffset: CMTime = .zero
    private var pauseAnchor: CMTime?
    private var clipIndex = 0

    func beginClipIfNeeded(at time: CMTime) {
        guard !currentClipHasStarted else { return }
        currentClipHasStarted = true
        currentClipStart = time
        currentClipEnd = time
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

    func finalizeCurrentClipIfNeeded(preferredEndTime: CMTime? = nil) {
        guard currentClipHasStarted,
              let currentClipStart,
              let currentClipEnd else {
            resetCurrentClipFlags()
            return
        }
        let endTime: CMTime
        if let preferredEndTime, preferredEndTime > currentClipStart {
            endTime = preferredEndTime
        } else {
            endTime = currentClipEnd
        }
        let duration = max(endTime - currentClipStart, .zero)
        clips.append(
            RecordedClipSegment(
                index: clipIndex,
                startedAt: currentClipStart,
                endedAt: endTime,
                duration: duration
            )
        )
        totalDuration = clips.reduce(.zero) { $0 + $1.duration }
        clipIndex += 1
        resetCurrentClipFlags()
    }

    func makeRecordedClip(outputURL: URL, fallbackStartedAt: CMTime?, fallbackEndedAt: CMTime?) -> RecordedClip {
        let startedAt = clips.first?.startedAt ?? fallbackStartedAt
        let endedAt = clips.last?.endedAt ?? fallbackEndedAt
        let total = clips.reduce(.zero) { $0 + $1.duration }
        return RecordedClip(
            outputURL: outputURL,
            duration: total,
            startedAt: startedAt,
            endedAt: endedAt,
            segments: clips
        )
    }

    func snapshot() -> RecordingSessionStateSnapshot {
        RecordingSessionStateSnapshot(
            currentClipHasStarted: currentClipHasStarted,
            currentClipHasVideo: currentClipHasVideo,
            currentClipHasAudio: currentClipHasAudio,
            clipCount: clips.count,
            totalDuration: totalDuration,
            currentClipDuration: currentClipDuration
        )
    }

    private func updateClipTiming(with time: CMTime) {
        currentClipEnd = time
        if let currentClipStart {
            currentClipDuration = max(time - currentClipStart, .zero)
        }
    }

    private func resetCurrentClipFlags() {
        currentClipHasStarted = false
        currentClipHasVideo = false
        currentClipHasAudio = false
        currentClipStart = nil
        currentClipEnd = nil
        currentClipDuration = .zero
    }
}
