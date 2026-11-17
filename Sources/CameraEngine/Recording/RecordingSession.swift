// 作者：Condy
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

/// 暂停锚点始终位于输入时间域；片段和 Writer 使用扣除暂停后的媒体时间。
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
    var requiresResume: Bool { pauseAnchor != nil }
    var mediaEnd: CMTime? { currentClipEnd ?? clips.last?.endedAt }

    func beginClipIfNeeded(at time: CMTime) {
        guard !currentClipHasStarted else { return }
        currentClipHasStarted = true
        currentClipStart = time; currentClipEnd = time; currentClipDuration = .zero
        currentClipHasVideo = false; currentClipHasAudio = false
    }
    func markVideoFrame(at time: CMTime, duration: CMTime = CMTime(value: 1, timescale: 30)) {
        beginClipIfNeeded(at: time); currentClipHasVideo = true
        updateClipTiming(with: time, duration: duration)
    }
    func markAudioFrame(at time: CMTime, duration: CMTime = .zero) {
        beginClipIfNeeded(at: time); currentClipHasAudio = true
        updateClipTiming(with: time, duration: duration)
    }
    func pause(at inputTime: CMTime) { pauseAnchor = inputTime }
    func resume(at inputTime: CMTime) {
        guard let pauseAnchor else { return }
        timeOffset = timeOffset + max(inputTime - pauseAnchor, .zero)
        self.pauseAnchor = nil
    }
    func normalizedTime(for inputTime: CMTime) -> CMTime { inputTime - timeOffset }
    func inputTime(for mediaTime: CMTime) -> CMTime { mediaTime + timeOffset }

    func finalizeCurrentClipIfNeeded(preferredEndTime: CMTime? = nil) {
        guard currentClipHasStarted, let start = currentClipStart, let end = currentClipEnd else { return }
        let resolvedEnd = max(end, preferredEndTime ?? end)
        let duration = max(resolvedEnd - start, .zero)
        clips.append(RecordedClipSegment(index: clipIndex, startedAt: start, endedAt: resolvedEnd,
            duration: duration, containsVideo: currentClipHasVideo, containsAudio: currentClipHasAudio))
        totalDuration = totalDuration + duration; clipIndex += 1
        currentClipHasStarted = false; currentClipHasVideo = false; currentClipHasAudio = false
        currentClipStart = nil; currentClipEnd = nil; currentClipDuration = .zero
    }
    func makeRecordedClip(outputURL: URL, fallbackStartedAt: CMTime?, fallbackEndedAt: CMTime?,
        infoDictionary: [String: Any]? = nil, recordingCadence: RecordingCadence? = nil) -> RecordedClip {
        let start = clips.first?.startedAt ?? fallbackStartedAt
        let end = clips.last?.endedAt ?? fallbackEndedAt
        let video = clips.contains(where: \.containsVideo); let audio = clips.contains(where: \.containsAudio)
        return RecordedClip(outputURL: outputURL, duration: totalDuration, startedAt: start, endedAt: end,
            segments: clips, infoDictionary: infoDictionary, thumbnailTime: .zero, sessionManifest: [
                "clipCount": clips.count, "segmentCount": clips.count,
                "videoSegments": clips.filter(\.containsVideo).count, "audioSegments": clips.filter(\.containsAudio).count,
                "containsVideo": video, "containsAudio": audio, "totalDurationSeconds": totalDuration.seconds,
                "startedAtSeconds": start?.seconds ?? 0, "endedAtSeconds": end?.seconds ?? 0
            ], recordingCadence: recordingCadence)
    }
    func snapshot() -> RecordingSessionStateSnapshot {
        RecordingSessionStateSnapshot(currentClipHasStarted: currentClipHasStarted, currentClipHasVideo: currentClipHasVideo,
            currentClipHasAudio: currentClipHasAudio, clipCount: clips.count, totalDuration: totalDuration,
            currentClipDuration: currentClipDuration, segmentCount: clips.count,
            recordedVideoSegmentCount: clips.filter(\.containsVideo).count, recordedAudioSegmentCount: clips.filter(\.containsAudio).count)
    }
    private func updateClipTiming(with time: CMTime, duration: CMTime) {
        let sampleEnd = time + (duration.isNumeric && duration > .zero ? duration : .zero)
        currentClipEnd = max(currentClipEnd ?? time, sampleEnd)
        currentClipDuration = max((currentClipEnd ?? time) - (currentClipStart ?? time), .zero)
    }
}
