//
//  CameraVideoFormatSelection.swift
//  KakaposCamera
//
//  Created by Condy on 2026/11/16.
//

import AVFoundation
import CoreGraphics
import Foundation
import KakaposVideo

public enum CameraVideoFormatSelectionPolicy: Equatable, Sendable {
    case bestEffort
    case requireRequested
}

public enum CameraVideoSpecificationError: Error, Equatable {
    case invalidRequest
    case unsupportedSpecification
}

/// 设备候选的纯数据投影，选择逻辑可在无相机的宿主验证。
public struct CameraVideoFormatCandidate: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let frameRateRanges: [CameraFrameRateRange]
    public let colorPolicies: [VideoExportColorPolicy]

    public init(width: Int, height: Int, frameRateRanges: [CameraFrameRateRange],
        colorPolicies: [VideoExportColorPolicy] = [.sourceCompatible, .standardBT709]) {
        self.width = width
        self.height = height
        self.frameRateRanges = frameRateRanges
        self.colorPolicies = colorPolicies
    }
}

/// 配置完成后的设备状态；帧率范围不是逐帧实测帧率，后者由RecordingCadence描述。
public struct CameraVideoSpecification: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let minimumFrameRate: Double?
    public let maximumFrameRate: Double?
    public let pixelFormat: UInt32?
    public let stabilizationMode: Int?
    public let deviceIdentifier: String

    public init(width: Int, height: Int, minimumFrameRate: Double?, maximumFrameRate: Double?,
        pixelFormat: UInt32?, stabilizationMode: Int?, deviceIdentifier: String) {
        self.width = width
        self.height = height
        self.minimumFrameRate = minimumFrameRate
        self.maximumFrameRate = maximumFrameRate
        self.pixelFormat = pixelFormat
        self.stabilizationMode = stabilizationMode
        self.deviceIdentifier = deviceIdentifier
    }
}

extension CameraFrameRateRange {
    /// 常用整数和NTSC时钟精确表示；其余正帧率按微帧率精度约分。
    public func frameDurations() throws -> (minimum: CMTime, maximum: CMTime) {
        guard minimumFramesPerSecond.isFinite, maximumFramesPerSecond.isFinite,
              minimumFramesPerSecond > 0, maximumFramesPerSecond >= minimumFramesPerSecond else {
            throw CameraVideoSpecificationError.invalidRequest
        }
        return (try Self.duration(for: maximumFramesPerSecond), try Self.duration(for: minimumFramesPerSecond))
    }

    private static func duration(for fps: Double) throws -> CMTime {
        if fps.rounded() == fps, fps <= Double(Int32.max) { return CMTime(value: 1, timescale: Int32(fps)) }
        for numerator in [24_000, 30_000, 60_000, 120_000] where abs(fps - Double(numerator) / 1001) < 1e-9 {
            return CMTime(value: 1001, timescale: Int32(numerator))
        }
        let scaled = (fps * 1_000_000).rounded()
        guard scaled >= 1, scaled <= Double(Int32.max) else { throw CameraVideoSpecificationError.invalidRequest }
        var a = Int64(scaled)
        var b: Int64 = 1_000_000
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return CMTime(value: 1_000_000 / a, timescale: Int32(Int64(scaled) / a))
    }
}

extension CameraVideoConfiguration {
    public func accepts(_ actual: CameraVideoSpecification) -> Bool {
        guard formatSelectionPolicy == .requireRequested else { return true }
        guard let dimensions = captureDimensions, dimensions.width == CGFloat(actual.width), dimensions.height == CGFloat(actual.height) else { return false }
        guard let rate = preferredFrameRateRange else { return true }
        guard let minimum = actual.minimumFrameRate, let maximum = actual.maximumFrameRate else { return false }
        return abs(minimum - rate.minimumFramesPerSecond) < 1e-5 && abs(maximum - rate.maximumFramesPerSecond) < 1e-5
    }

    /// 宽松默认不接管系统格式选择；严格模式必须给出明确的传感器格式尺寸。
    public func preferredFormatIndex(in candidates: [CameraVideoFormatCandidate], currentIndex: Int? = nil) throws -> Int? {
        guard formatSelectionPolicy == .requireRequested || colorPolicy != .sourceCompatible else { return nil }
        let currentSize = currentIndex.flatMap { candidates.indices.contains($0) ? CGSize(width: candidates[$0].width, height: candidates[$0].height) : nil }
        let requestedSize = formatSelectionPolicy == .requireRequested ? captureDimensions : (captureDimensions ?? dimensions ?? currentSize)
        guard let dimensions = requestedSize,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0,
              dimensions.width.rounded() == dimensions.width, dimensions.height.rounded() == dimensions.height,
              dimensions.width <= CGFloat(Int32.max), dimensions.height <= CGFloat(Int32.max) else {
            throw CameraVideoSpecificationError.invalidRequest
        }
        if let range = preferredFrameRateRange { _ = try range.frameDurations() }
        func matches(_ candidate: CameraVideoFormatCandidate) -> Bool {
            guard candidate.width == Int(dimensions.width), candidate.height == Int(dimensions.height),
                  colorPolicy == .sourceCompatible || candidate.colorPolicies.contains(colorPolicy) else { return false }
            guard let requested = preferredFrameRateRange else { return true }
            return candidate.frameRateRanges.contains {
                $0.minimumFramesPerSecond <= requested.minimumFramesPerSecond
                    && $0.maximumFramesPerSecond >= requested.maximumFramesPerSecond
            }
        }
        if let currentIndex, candidates.indices.contains(currentIndex), matches(candidates[currentIndex]) { return currentIndex }
        guard let index = candidates.firstIndex(where: matches) else { throw CameraVideoSpecificationError.unsupportedSpecification }
        return index
    }
}
