//
//  RotateCommand.swift
//  VideoBox
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

public struct RotateCommand {
    
    public let angle: Float
    public init(angle: Float) {
        let value = angle.truncatingRemainder(dividingBy: 360.0)
        self.angle = value >= 0 ? value : 360 + value
    }
}

extension RotateCommand: Command {
    public func execute(export: AVAssetExportSession, tracks: Tracks, videoComposition: AVMutableVideoComposition) {
        let width  = videoComposition.renderSize.width
        let height = videoComposition.renderSize.height
        let radians = CGFloat(angle * Float.pi / 180.0)
        var transform: CGAffineTransform
        switch angle {
        case 0...90:
            transform = CGAffineTransform(translationX: height, y: 0.0)
        case 90..<180:
            transform = CGAffineTransform(translationX: 0.0, y: height)
        case 180:
            transform = CGAffineTransform(translationX: width, y: height)
        case 180..<270:
            transform = CGAffineTransform(translationX: 0.0, y: width)
        case 270:
            transform = CGAffineTransform(translationX: 0.0, y: width)
        case 270..<360:
            transform = CGAffineTransform(translationX: height, y: width)
        default:
            transform = .identity
        }
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks.videoTrack)
        layerInstruction.trackID = tracks.videoTrack.trackID
        layerInstruction.setTransform(transform.rotated(by: radians), at: .zero)
        
        if let instruction = videoComposition.instructions.last as? AVMutableVideoCompositionInstruction {
            instruction.layerInstructions.append(layerInstruction)
            videoComposition.instructions = [instruction]
        } else {
            let duration = tracks.videoTrack.timeRange.duration
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(start: .zero, duration: duration)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
        }
        
        let w = abs(sin(radians) * height) + abs(cos(radians) * width)
        let h = abs(sin(radians) * width) + abs(cos(radians) * height)
        videoComposition.renderSize = CGSize(width: w, height: h)
    }
}

extension RotateCommand {
    // 矩阵校正
    // x' = ax + cy + tx     y' = bx + dy + ty
    private func transform(degree: Int, natureSize: CGSize) -> CGAffineTransform {
        if degree == 90 {
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: natureSize.height, ty: 0)
        } else if degree == 180 {
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: natureSize.width, ty: natureSize.height)
        } else if degree == 270 {
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: natureSize.width)
        } else {
            return .identity
        }
    }
    
    private func getDegree(_ t: CGAffineTransform) -> Int {
        var degree: Int = 0
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 {
            degree = 90
        } else if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 {
            degree = 270
        } else if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 {
            degree = 180
        } else if t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 {
            degree = 0
        }
        return degree
    }
}
