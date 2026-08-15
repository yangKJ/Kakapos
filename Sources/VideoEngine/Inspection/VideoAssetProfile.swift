//
//  VideoAssetProfile.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import CoreGraphics
import CoreMedia
import Foundation
import KakaposMediaCore

public enum VideoAssetCodec: Equatable, Hashable, Sendable {
    case h264
    case hevc
    case jpeg
    case proRes
    case other(fourCC: UInt32)
    case unknown
}

public enum VideoAssetAudioCodec: Equatable, Hashable, Sendable {
    case aac
    case linearPCM
    case other(fourCC: UInt32)
    case unknown
}

public struct VideoAssetProfile: Equatable, @unchecked Sendable {
    public let duration: CMTime
    public let presentationSize: CGSize
    public let preferredTransform: CGAffineTransform
    public let videoTrackCount: Int
    public let videoCodec: VideoAssetCodec
    /// 压缩资产的色彩事实。解码前 `pixelFormat` 通常为 `.unknown`，不应用于 processor 像素格式准入。
    public let frameFormat: FrameFormat
    public let nominalFramesPerSecond: Double
    public let minimumFrameDuration: CMTime?
    public let audioTrackCount: Int
    public let audioCodec: VideoAssetAudioCodec?

    public init(
        duration: CMTime,
        presentationSize: CGSize,
        preferredTransform: CGAffineTransform,
        videoTrackCount: Int,
        videoCodec: VideoAssetCodec,
        frameFormat: FrameFormat,
        nominalFramesPerSecond: Double,
        minimumFrameDuration: CMTime?,
        audioTrackCount: Int,
        audioCodec: VideoAssetAudioCodec?
    ) {
        self.duration = duration
        self.presentationSize = presentationSize
        self.preferredTransform = preferredTransform
        self.videoTrackCount = videoTrackCount
        self.videoCodec = videoCodec
        self.frameFormat = frameFormat
        self.nominalFramesPerSecond = nominalFramesPerSecond
        self.minimumFrameDuration = minimumFrameDuration
        self.audioTrackCount = audioTrackCount
        self.audioCodec = audioCodec
    }
}

public enum VideoAssetProfileInspectionError: Error, Equatable {
    case videoTrackMissing
}
