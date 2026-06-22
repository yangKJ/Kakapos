//
//  MediaFrame.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
#if canImport(Metal)
import Metal
#endif

public struct FrameMetadata {
    public var presentationTime: CMTime
    public var duration: CMTime?
    public var sourceTime: CMTime?
    public var trackTransform: CGAffineTransform
    public var frameIndex: Int64?
    public var userInfo: [String: Any]

    public init(
        presentationTime: CMTime,
        duration: CMTime? = nil,
        sourceTime: CMTime? = nil,
        trackTransform: CGAffineTransform = .identity,
        frameIndex: Int64? = nil,
        userInfo: [String: Any] = [:]
    ) {
        self.presentationTime = presentationTime
        self.duration = duration
        self.sourceTime = sourceTime
        self.trackTransform = trackTransform
        self.frameIndex = frameIndex
        self.userInfo = userInfo
    }
}

public struct MediaFrame {
    public var pixelBuffer: CVPixelBuffer?
    public var sampleBuffer: CMSampleBuffer?
    #if canImport(Metal)
    public var texture: MTLTexture?
    #endif
    public var metadata: FrameMetadata

    public init(pixelBuffer: CVPixelBuffer, metadata: FrameMetadata) {
        self.pixelBuffer = pixelBuffer
        self.sampleBuffer = nil
        #if canImport(Metal)
        self.texture = nil
        #endif
        self.metadata = metadata
    }

    public init(sampleBuffer: CMSampleBuffer, metadata: FrameMetadata? = nil) {
        self.pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        self.sampleBuffer = sampleBuffer
        #if canImport(Metal)
        self.texture = nil
        #endif
        let timing = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.metadata = metadata ?? FrameMetadata(
            presentationTime: timing,
            duration: CMSampleBufferGetDuration(sampleBuffer).isValid ? CMSampleBufferGetDuration(sampleBuffer) : nil,
            sourceTime: timing
        )
    }

    #if canImport(Metal)
    public init(texture: MTLTexture, metadata: FrameMetadata) {
        self.pixelBuffer = nil
        self.sampleBuffer = nil
        self.texture = texture
        self.metadata = metadata
    }
    #endif
}
