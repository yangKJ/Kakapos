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
    case hdrHLG
    case hdrPQ

    public var isHDR: Bool { self == .hdrHLG || self == .hdrPQ }

    public var requestedDynamicRange: FrameDynamicRange? {
        switch self {
        case .hdrHLG: return .hdr(.hlg)
        case .hdrPQ: return .hdr(.pq)
        case .standardBT709: return .standard
        case .sourceCompatible: return nil
        }
    }

    var pixelBufferFormat: OSType { isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA }

    var colorProperties: [String: Any]? {
        switch self {
        case .sourceCompatible: return nil
        case .standardBT709:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        case .hdrHLG, .hdrPQ:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020, AVVideoTransferFunctionKey: self == .hdrHLG ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
        }
    }
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
