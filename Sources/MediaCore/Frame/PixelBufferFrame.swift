//
//  PixelBufferFrame.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import CoreVideo

/// 以 `CVPixelBuffer` 作为主 payload 的帧。
///
/// 适用于原始像素缓冲区来源，或只需读取像素的消费者。
public struct PixelBufferFrame: MediaFrame {
    public let pixelBuffer: CVPixelBuffer
    public var metadata: FrameMetadata

    public init(pixelBuffer: CVPixelBuffer, metadata: FrameMetadata) {
        self.pixelBuffer = pixelBuffer
        self.metadata = metadata
    }
}
