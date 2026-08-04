//
//  VideoArtifactValidator.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import AVFoundation
import Foundation

public struct VideoArtifactValidationExpectation: @unchecked Sendable {
    public let sourceDuration: CMTime
    public let expectsAudio: Bool
    public let durationTolerance: CMTime

    public init(
        sourceDuration: CMTime,
        expectsAudio: Bool,
        durationTolerance: CMTime = CMTime(seconds: 0.12, preferredTimescale: 600)
    ) {
        self.sourceDuration = sourceDuration
        self.expectsAudio = expectsAudio
        self.durationTolerance = durationTolerance
    }
}

public struct VideoArtifactValidationReport: @unchecked Sendable {
    public let url: URL
    public let duration: CMTime
    public let videoTrackCount: Int
    public let audioTrackCount: Int
    public let naturalSize: CGSize
    public let preferredTransform: CGAffineTransform

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

        return VideoArtifactValidationReport(
            url: url,
            duration: duration,
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count,
            naturalSize: videoTrack.naturalSize,
            preferredTransform: videoTrack.preferredTransform
        )
    }
}
