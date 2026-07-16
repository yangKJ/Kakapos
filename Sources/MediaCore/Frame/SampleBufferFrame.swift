//
//  SampleBufferFrame.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
import CoreVideo

/// 以 `CMSampleBuffer` 作为主 payload 的帧。
///
/// 适用于相机、`AVAssetReader`、`AVPlayer` 等 AVFoundation 来源，
/// 以及需要完整 timing、format、attachment 信息的消费者。
/// `pixelBuffer` 是派生访问入口，便于只读取像素的兼容调用方使用。
public struct SampleBufferFrame: MediaFrame {
    public let sampleBuffer: CMSampleBuffer
    public var metadata: FrameMetadata

    public init(sampleBuffer: CMSampleBuffer, metadata: FrameMetadata? = nil) {
        self.sampleBuffer = sampleBuffer
        if let metadata = metadata {
            self.metadata = metadata
        } else {
            let timing = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            self.metadata = FrameMetadata(
                presentationTime: timing,
                duration: CMSampleBufferGetDuration(sampleBuffer).isValid ? CMSampleBufferGetDuration(sampleBuffer) : nil,
                sourceTime: timing
            )
        }
    }

    /// 便捷访问底层图像缓冲区。
    public var pixelBuffer: CVPixelBuffer? {
        CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}
