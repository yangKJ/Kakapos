//
//  MediaFrame.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//
//  `MediaFrame` 保持最小协议，只暴露领域元数据。
//  AVFoundation / Metal payload 不进入协议，避免抽象被具体后端污染；
//  `PixelBufferFrame`、`SampleBufferFrame`、`TextureFrame` 各自持有 payload。
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
#if canImport(Metal)
import Metal
#endif

public struct FrameMetadata: @unchecked Sendable {
    public var presentationTime: CMTime
    public var duration: CMTime?
    public var sourceTime: CMTime?
    public var trackTransform: CGAffineTransform
    public var frameIndex: Int64?
    public var format: FrameFormat?
    public var userInfo: [String: Any]

    public init(
        presentationTime: CMTime,
        duration: CMTime? = nil,
        sourceTime: CMTime? = nil,
        trackTransform: CGAffineTransform = .identity,
        frameIndex: Int64? = nil,
        format: FrameFormat? = nil,
        userInfo: [String: Any] = [:]
    ) {
        self.presentationTime = presentationTime
        self.duration = duration
        self.sourceTime = sourceTime
        self.trackTransform = trackTransform
        self.frameIndex = frameIndex
        self.format = format
        self.userInfo = userInfo
    }
}

public protocol MediaFrame {
    var metadata: FrameMetadata { get set }
}

public extension MediaFrame {
    /// 为仅需像素缓冲区的调用方保留兼容访问入口。
    /// 新代码在 payload 区分有意义时应使用显式类型。
    var pixelBuffer: CVPixelBuffer? {
        extractPixelBuffer(self)
    }

    /// 为 AVFoundation 原生调用方保留兼容访问入口。
    var sampleBuffer: CMSampleBuffer? {
        extractSampleBuffer(self)
    }

    #if canImport(Metal)
    /// 为 Metal 原生调用方保留兼容访问入口。
    var texture: MTLTexture? {
        extractTexture(self)
    }
    #endif
}

public func extractPixelBuffer(_ frame: MediaFrame) -> CVPixelBuffer? {
    if let p = frame as? PixelBufferFrame { return p.pixelBufferPayload }
    if let s = frame as? SampleBufferFrame {
        return CMSampleBufferGetImageBuffer(s.sampleBufferPayload)
    }
    return nil
}

public func extractSampleBuffer(_ frame: MediaFrame) -> CMSampleBuffer? {
    (frame as? SampleBufferFrame)?.sampleBufferPayload
}

#if canImport(Metal)
public func extractTexture(_ frame: MediaFrame) -> MTLTexture? {
    (frame as? TextureFrame)?.texturePayload
}
#endif
