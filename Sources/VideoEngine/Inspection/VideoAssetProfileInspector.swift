//
//  VideoAssetProfileInspector.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import AVFoundation
import CoreMedia
import Foundation
import KakaposMediaCore

public struct VideoAssetProfileInspector: Sendable {
    public init() {}

    /// 读取已经可用的本地轨道属性。远端或 iCloud 资产应优先使用 ``inspectLoaded(_:)``。
    public func inspect(_ asset: AVAsset) throws -> VideoAssetProfile {
        let duration = asset.duration

        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoAssetProfileInspectionError.videoTrackMissing
        }
        let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let presentationSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let videoDescription = Self.makeFormatDescription(from: videoTrack.formatDescriptions)
        let audioTracks = asset.tracks(withMediaType: .audio)
        let audioDescription = audioTracks.first.flatMap { Self.makeFormatDescription(from: $0.formatDescriptions) }
        let minimumFrameDuration = videoTrack.minFrameDuration

        return VideoAssetProfile(
            duration: duration,
            presentationSize: presentationSize,
            preferredTransform: videoTrack.preferredTransform,
            videoTrackCount: videoTracks.count,
            videoCodec: Self.videoCodec(from: videoDescription),
            frameFormat: Self.frameFormat(from: videoDescription),
            nominalFramesPerSecond: Double(videoTrack.nominalFrameRate),
            minimumFrameDuration: minimumFrameDuration.isValid && minimumFrameDuration.isNumeric ? minimumFrameDuration : nil,
            audioTrackCount: audioTracks.count,
            audioCodec: audioTracks.isEmpty ? nil : Self.audioCodec(from: audioDescription)
        )
    }

    /// 在系统支持时先异步加载轨道属性，避免远端或 iCloud 资产被同步属性读取误判。
    public func inspectLoaded(_ asset: AVAsset) async throws -> VideoAssetProfile {
        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw VideoAssetProfileInspectionError.videoTrackMissing
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let videoDescriptions = try await videoTrack.load(.formatDescriptions)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let minimumFrameDuration = try await videoTrack.load(.minFrameDuration)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audioDescription: CMFormatDescription?
            if let audioTrack = audioTracks.first {
                audioDescription = try await audioTrack.load(.formatDescriptions).first
            } else {
                audioDescription = nil
            }
            return VideoAssetProfile(
                duration: duration,
                presentationSize: CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height)),
                preferredTransform: preferredTransform,
                videoTrackCount: videoTracks.count,
                videoCodec: Self.videoCodec(from: videoDescriptions.first),
                frameFormat: Self.frameFormat(from: videoDescriptions.first),
                nominalFramesPerSecond: Double(nominalFrameRate),
                minimumFrameDuration: minimumFrameDuration.isValid && minimumFrameDuration.isNumeric ? minimumFrameDuration : nil,
                audioTrackCount: audioTracks.count,
                audioCodec: audioTracks.isEmpty ? nil : Self.audioCodec(from: audioDescription)
            )
        }
        return try inspect(asset)
    }

    public static func videoCodec(fourCC: FourCharCode?) -> VideoAssetCodec {
        guard let fourCC else { return .unknown }
        switch fourCC {
        case kCMVideoCodecType_H264:
            return .h264
        case kCMVideoCodecType_HEVC:
            return .hevc
        case kCMVideoCodecType_JPEG:
            return .jpeg
        case kCMVideoCodecType_AppleProRes422,
             kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT,
             kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes4444:
            return .proRes
        default:
            return .other(fourCC: fourCC)
        }
    }

    public static func audioCodec(fourCC: FourCharCode?) -> VideoAssetAudioCodec {
        guard let fourCC else { return .unknown }
        switch fourCC {
        case kAudioFormatMPEG4AAC:
            return .aac
        case kAudioFormatLinearPCM:
            return .linearPCM
        default:
            return .other(fourCC: fourCC)
        }
    }

    private static func videoCodec(from description: CMFormatDescription?) -> VideoAssetCodec {
        videoCodec(fourCC: description.map(CMFormatDescriptionGetMediaSubType))
    }

    private static func audioCodec(from description: CMFormatDescription?) -> VideoAssetAudioCodec {
        audioCodec(fourCC: description.map(CMFormatDescriptionGetMediaSubType))
    }

    private static func makeFormatDescription(from descriptions: [Any]) -> CMFormatDescription? {
        guard let first = descriptions.first else { return nil }
        let object = first as AnyObject
        guard CFGetTypeID(object) == CMFormatDescriptionGetTypeID() else { return nil }
        return unsafeBitCast(object, to: CMFormatDescription.self)
    }

    private static func frameFormat(from description: CMFormatDescription?) -> FrameFormat {
        guard let description else {
            return FrameFormat(pixelFormat: .unknown, colorInfo: unknownColorInfo, dynamicRange: .unknown)
        }
        guard let rawExtensions = CMFormatDescriptionGetExtensions(description) else {
            return FrameFormat(pixelFormat: .unknown, colorInfo: unknownColorInfo, dynamicRange: .unknown)
        }
        let extensions = rawExtensions as NSDictionary
        let primariesValue = stringValue(extensions[kCMFormatDescriptionExtension_ColorPrimaries])
        let transferValue = stringValue(extensions[kCMFormatDescriptionExtension_TransferFunction])
        let matrixValue = stringValue(extensions[kCMFormatDescriptionExtension_YCbCrMatrix])
        let transfer = transferFunction(transferValue)
        let dynamicRange: FrameDynamicRange
        switch transfer {
        case .hlg, .pq:
            dynamicRange = .hdr(transfer)
        case .sdr:
            dynamicRange = .standard
        case .unknown:
            dynamicRange = .unknown
        }
        return FrameFormat(
            // 压缩轨道描述的是编码格式而非解码后的 CVPixelBuffer；真实像素格式只能在逐帧解码后确定。
            pixelFormat: .unknown,
            colorInfo: FrameColorInfo(
                primaries: colorPrimaries(primariesValue),
                transferFunction: transfer,
                yCbCrMatrix: yCbCrMatrix(matrixValue)
            ),
            dynamicRange: dynamicRange
        )
    }

    private static let unknownColorInfo = FrameColorInfo(
        primaries: .unknown(nil),
        transferFunction: .unknown(nil),
        yCbCrMatrix: .unknown(nil)
    )

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        return String(describing: value)
    }

    private static func colorPrimaries(_ value: String?) -> FrameColorPrimaries {
        guard let value else { return .unknown(nil) }
        if value.contains("709") { return .bt709 }
        if value.contains("2020") { return .bt2020 }
        if value.localizedCaseInsensitiveContains("P3") { return .p3D65 }
        return .unknown(value)
    }

    private static func transferFunction(_ value: String?) -> FrameTransferFunction {
        guard let value else { return .unknown(nil) }
        if value.localizedCaseInsensitiveContains("HLG") || value.contains("2100_HLG") { return .hlg }
        if value.localizedCaseInsensitiveContains("PQ") || value.contains("2084") { return .pq }
        if value.contains("709") || value.localizedCaseInsensitiveContains("sRGB") { return .sdr }
        return .unknown(value)
    }

    private static func yCbCrMatrix(_ value: String?) -> FrameYCbCrMatrix {
        guard let value else { return .unknown(nil) }
        if value.contains("601") { return .bt601 }
        if value.contains("709") { return .bt709 }
        if value.contains("2020") { return .bt2020 }
        if value.localizedCaseInsensitiveContains("identity") { return .identity }
        return .unknown(value)
    }
}
