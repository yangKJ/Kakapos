//
//  FrameProcessingPlan.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import Foundation
import AVFoundation
import KakaposMediaCore

public struct FrameProcessingPlan: @unchecked Sendable {
    public struct Identity: Hashable, Sendable, Codable {
        public let identifier: String
        public let revision: String

        public init(identifier: String, revision: String) {
            self.identifier = identifier
            self.revision = revision
        }
    }

    public let identity: Identity
    private let processorFactory: () throws -> [FrameProcessor]

    public init(
        identity: Identity,
        makeProcessors: @escaping () throws -> [FrameProcessor]
    ) {
        self.identity = identity
        self.processorFactory = makeProcessors
    }

    public func makeProcessors() throws -> [FrameProcessor] {
        let processors = try processorFactory()
        guard processors.isEmpty == false else {
            throw FrameProcessingPlanError.emptyProcessorChain
        }
        return processors
    }
}

public enum FrameProcessingPlanError: Error, Equatable {
    case emptyProcessorChain
}

/// 只有每个处理器显式接纳原生格式，且源编码不含 alpha 时才协商为 YUV。
func negotiatedVideoPixelFormat(processors: [FrameProcessor], fallback: OSType, sourceCodec: FourCharCode?, sourceDynamicRange: FrameDynamicRange = .standard) -> OSType {
    guard fallback == kCVPixelFormatType_32BGRA, sourceDynamicRange == .standard, !processors.isEmpty,
          sourceCodec == kCMVideoCodecType_H264 || sourceCodec == kCMVideoCodecType_HEVC else { return fallback }
    for candidate in [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
        if processors.allSatisfy({ ($0 as? FrameProcessorCapabilityProviding)?.capabilities.acceptedPixelFormats.contains(FramePixelFormat(ostype: candidate)) == true }) {
            return candidate
        }
    }
    return fallback
}
