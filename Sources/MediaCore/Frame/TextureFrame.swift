//
//  TextureFrame.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation
#if canImport(Metal)
import Metal
#endif

/// 以 `MTLTexture` 作为主 payload 的帧。
///
/// 适用于来源已经生成 Metal 纹理，且消费者直接渲染纹理的场景。
/// 仅在具备 Metal 的平台上可用。
#if canImport(Metal)
public struct TextureFrame: MediaFrame {
    public let texture: MTLTexture
    public var metadata: FrameMetadata

    public init(texture: MTLTexture, metadata: FrameMetadata) {
        self.texture = texture
        self.metadata = metadata
    }
}
#endif
