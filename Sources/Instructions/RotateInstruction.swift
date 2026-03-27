//
//  RotateInstruction.swift
//  Kakapos
//
//  Created by Condy on 2024/4/12.
//

import Foundation
import AVFoundation
import CoreVideo

public enum RotationAngle: Int, CaseIterable {
    case angle0   = 0
    case angle90  = 90
    case angle180 = 180
    case angle270 = 270
    
    var radians: CGFloat {
        return CGFloat(self.rawValue) * .pi / 180.0
    }
    
    var shouldSwapDimensions: Bool {
        return self == .angle90 || self == .angle270
    }
    
    /// For mov video, adjust the rotation angle and rotate 90 degrees less.
    /// For mp4 videos, normal processing of rotation.
    func rotation(isMovVideo: Bool, renderSize: CGSize) -> (x: CGFloat, y: CGFloat, angle: CGFloat)? {
        switch self {
        case .angle0:
            return isMovVideo ? (x: 0, y: renderSize.height, angle: -.pi / 2) : nil
        case .angle90:
            return isMovVideo ? nil : (x: renderSize.width, y: 0, angle: .pi / 2)
        case .angle180:
            return isMovVideo ? (x: renderSize.width, y: 0, angle: .pi / 2) : (x: renderSize.width, y: renderSize.height, angle: .pi)
        case .angle270:
            return isMovVideo ? (x: renderSize.width, y: renderSize.height, angle: .pi) : (x: 0, y: renderSize.height, angle: -.pi / 2)
        }
    }
}

/// Rotation instruction - realize fixed-angle rotation
public final class RotateInstruction: Instruction, InstructionProtocol, @unchecked Sendable {
    
    public let rotationAngle: RotationAngle
    
    public init(rotationAngle: RotationAngle) {
        self.rotationAngle = rotationAngle
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func setup() {
        super.setup()
    }
    
    public func rotatedSize(from originalSize: CGSize) -> CGSize {
        if rotationAngle.shouldSwapDimensions {
            return CGSize(width: originalSize.height, height: originalSize.width)
        }
        return originalSize
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        block(buffer)
    }
}
