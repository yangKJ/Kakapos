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
public enum TextureFrameCoordinateSpace: Equatable, Sendable {
    /// 原生 Metal 纹理，不附加 Core Image 坐标校正。
    case nativeMetal
    /// 从 CVPixelBuffer 桥接或渲染而来，显示时需恢复 PixelBuffer 的图像坐标合同。
    case pixelBuffer
}

public struct TextureFrame: MediaFrame {
    let texturePayload: MTLTexture
    public var metadata: FrameMetadata
    public let coordinateSpace: TextureFrameCoordinateSpace

    public var texture: MTLTexture {
        texturePayload
    }

    public init(
        texture: MTLTexture,
        metadata: FrameMetadata,
        coordinateSpace: TextureFrameCoordinateSpace = .nativeMetal
    ) {
        self.texturePayload = texture
        self.metadata = metadata
        self.coordinateSpace = coordinateSpace
    }
}
#endif
