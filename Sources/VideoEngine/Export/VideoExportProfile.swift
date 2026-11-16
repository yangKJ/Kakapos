//
//  VideoExportProfile.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import AVFoundation
import Foundation
import CoreVideo
import VideoToolbox
import KakaposMediaCore

public enum VideoExportCodec: Equatable, Sendable {
    case automatic
    case h264
    case hevc
    case jpeg
}

public enum VideoExportColorPolicy: Equatable, Hashable, Sendable {
    case sourceCompatible
    case standardBT709
    case standardDisplayP3
    case hdrHLG
    case hdrPQ

    public var isHDR: Bool { self == .hdrHLG || self == .hdrPQ }

    public var requestedDynamicRange: FrameDynamicRange? {
        switch self {
        case .hdrHLG: return .hdr(.hlg)
        case .hdrPQ: return .hdr(.pq)
        case .standardBT709, .standardDisplayP3: return .standard
        case .sourceCompatible: return nil
        }
    }

    public var pixelBufferFormat: OSType { isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA }

    public var colorProperties: [String: Any]? {
        switch self {
        case .sourceCompatible: return nil
        case .standardBT709:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        case .standardDisplayP3:
            return [AVVideoColorPrimariesKey: kCVImageBufferColorPrimaries_P3_D65 as String,
                    AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        case .hdrHLG, .hdrPQ:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020, AVVideoTransferFunctionKey: self == .hdrHLG ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
        }
    }
}

public struct VideoExportProfile: Equatable, Sendable {
    /// 允许完整、未处理且编码兼容的本地素材保留原压缩样本与码率；默认继续重编码。
    public let copiesSamplesWhenCompatible: Bool
    /// 可选视频读取预取，范围 0...2；默认不增加缓冲和跨队列调度。
    public let videoReadAheadFrameCount: Int
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
        audioChannelCount: Int = 2,
        copiesSamplesWhenCompatible: Bool = false,
        videoReadAheadFrameCount: Int = 0
    ) {
        self.videoReadAheadFrameCount = min(max(videoReadAheadFrameCount, 0), 2)
        self.copiesSamplesWhenCompatible = copiesSamplesWhenCompatible
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

    public func resolvedAssetCodec(fileType: AVFileType) -> VideoAssetCodec {
        switch videoCodec {
        case .automatic:
            if colorPolicy.isHDR { return .hevc }
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

public enum VideoExportProfileError: Error {
    case incompatibleHDRCodec
    case hdrProcessorNotAdmitted
    case invalidHDROutput
}
