//
//  VideoExportProfile.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import AVFoundation
import Foundation

public enum VideoExportCodec: Equatable, Sendable {
    case automatic
    case h264
    case hevc
    case jpeg
}

public enum VideoExportColorPolicy: Equatable, Sendable {
    case sourceCompatible
    case standardBT709
}

public struct VideoExportProfile: Equatable, Sendable {
    public let videoCodec: VideoExportCodec
    public let averageVideoBitRate: Int?
    public let colorPolicy: VideoExportColorPolicy
    public let audioBitRate: Int
    public let audioSampleRate: Double
    public let audioChannelCount: Int

    public init(
        videoCodec: VideoExportCodec = .automatic,
        averageVideoBitRate: Int? = nil,
        colorPolicy: VideoExportColorPolicy = .sourceCompatible,
        audioBitRate: Int = 128_000,
        audioSampleRate: Double = 44_100,
        audioChannelCount: Int = 2
    ) {
        self.videoCodec = videoCodec
        self.averageVideoBitRate = averageVideoBitRate.flatMap { $0 > 0 ? $0 : nil }
        self.colorPolicy = colorPolicy
        self.audioBitRate = max(audioBitRate, 32_000)
        self.audioSampleRate = max(audioSampleRate, 8_000)
        self.audioChannelCount = min(max(audioChannelCount, 1), 8)
    }

    public static let legacyCompatible = VideoExportProfile()

    public static let standardDelivery = VideoExportProfile(
        videoCodec: .h264,
        colorPolicy: .standardBT709
    )

    func resolvedAssetCodec(fileType: AVFileType) -> VideoAssetCodec {
        switch videoCodec {
        case .automatic:
            return fileType == .mov ? .jpeg : .h264
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        case .jpeg:
            return .jpeg
        }
    }
}
