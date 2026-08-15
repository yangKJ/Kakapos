//
//  VideoArtifactValidator.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import AVFoundation
import Foundation
import KakaposMediaCore

public struct VideoArtifactValidationExpectation: @unchecked Sendable {
    public let sourceDuration: CMTime
    public let expectsAudio: Bool
    public let durationTolerance: CMTime
    public let expectedVideoCodec: VideoAssetCodec?
    public let expectedDynamicRange: FrameDynamicRange?
    public let maximumAudioVideoDurationDrift: CMTime

    public init(
        sourceDuration: CMTime,
        expectsAudio: Bool,
        durationTolerance: CMTime = CMTime(seconds: 0.12, preferredTimescale: 600),
        expectedVideoCodec: VideoAssetCodec? = nil,
        expectedDynamicRange: FrameDynamicRange? = nil,
        maximumAudioVideoDurationDrift: CMTime = CMTime(seconds: 0.12, preferredTimescale: 600)
    ) {
        self.sourceDuration = sourceDuration
        self.expectsAudio = expectsAudio
        self.durationTolerance = durationTolerance
        self.expectedVideoCodec = expectedVideoCodec
        self.expectedDynamicRange = expectedDynamicRange
        self.maximumAudioVideoDurationDrift = maximumAudioVideoDurationDrift
    }
}

public struct VideoArtifactValidationReport: @unchecked Sendable {
    public let url: URL
    public let duration: CMTime
    public let videoTrackCount: Int
    public let audioTrackCount: Int
    public let naturalSize: CGSize
    public let preferredTransform: CGAffineTransform
    public let videoCodec: VideoAssetCodec
    public let dynamicRange: FrameDynamicRange
    public let nominalFramesPerSecond: Double
    public let audioVideoDurationDrift: CMTime?

    public var hasAudio: Bool { audioTrackCount > 0 }
}

public enum VideoArtifactValidationError: Error, Equatable {
    case fileMissing
    case fileEmpty
    case videoTrackMissing
    case audioTrackMissing
    case invalidDuration
    case durationMismatch
    case invalidDimensions
    case unexpectedVideoCodec
    case unexpectedDynamicRange
    case invalidFrameRate
    case audioVideoDurationDrift
}

public enum VideoArtifactValidator {
    public static func validate(
        url: URL,
        expectation: VideoArtifactValidationExpectation
    ) throws -> VideoArtifactValidationReport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoArtifactValidationError.fileMissing
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw VideoArtifactValidationError.fileMissing
        }
        guard (values.fileSize ?? 0) > 0 else {
            throw VideoArtifactValidationError.fileEmpty
        }

        let asset = AVURLAsset(url: url)
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoArtifactValidationError.videoTrackMissing
        }
        let audioTracks = asset.tracks(withMediaType: .audio)
        if expectation.expectsAudio, audioTracks.isEmpty {
            throw VideoArtifactValidationError.audioTrackMissing
        }

        let duration = asset.duration
        guard duration.isValid, duration.isNumeric, duration.seconds > 0 else {
            throw VideoArtifactValidationError.invalidDuration
        }
        let durationDifference = abs(duration.seconds - expectation.sourceDuration.seconds)
        guard durationDifference <= max(0, expectation.durationTolerance.seconds) else {
            throw VideoArtifactValidationError.durationMismatch
        }

        let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        guard abs(transformedSize.width) >= 1, abs(transformedSize.height) >= 1 else {
            throw VideoArtifactValidationError.invalidDimensions
        }

        let profile = try VideoAssetProfileInspector().inspect(asset)
        if let expectedVideoCodec = expectation.expectedVideoCodec,
           profile.videoCodec != expectedVideoCodec {
            throw VideoArtifactValidationError.unexpectedVideoCodec
        }
        if let expectedDynamicRange = expectation.expectedDynamicRange,
           profile.frameFormat.dynamicRange != expectedDynamicRange {
            throw VideoArtifactValidationError.unexpectedDynamicRange
        }
        guard profile.nominalFramesPerSecond.isFinite, profile.nominalFramesPerSecond > 0 else {
            throw VideoArtifactValidationError.invalidFrameRate
        }

        let audioVideoDurationDrift: CMTime?
        if let audioTrack = audioTracks.first {
            let drift = abs(videoTrack.timeRange.duration.seconds - audioTrack.timeRange.duration.seconds)
            audioVideoDurationDrift = CMTime(seconds: drift, preferredTimescale: 600)
            guard drift <= max(0, expectation.maximumAudioVideoDurationDrift.seconds) else {
                throw VideoArtifactValidationError.audioVideoDurationDrift
            }
        } else {
            audioVideoDurationDrift = nil
        }

        return VideoArtifactValidationReport(
            url: url,
            duration: duration,
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count,
            naturalSize: videoTrack.naturalSize,
            preferredTransform: videoTrack.preferredTransform,
            videoCodec: profile.videoCodec,
            dynamicRange: profile.frameFormat.dynamicRange,
            nominalFramesPerSecond: profile.nominalFramesPerSecond,
            audioVideoDurationDrift: audioVideoDurationDrift
        )
    }
}
