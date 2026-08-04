//
//  VideoOrientation.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/10.
//

import Foundation
import AVFoundation

public enum VideoOrientation: Int {
    case up = 0
    case right = 90
    case down = 180
    case left = 270
}

extension VideoOrientation {
    
    init(videoTrack: AVAssetTrack) {
        let txf: CGAffineTransform = videoTrack.preferredTransform
        if txf.a == 0 && txf.b == 1.0 && txf.c == -1.0 && txf.d == 0 {
            self = .right
        } else if txf.a == 0 && txf.b == -1.0 && txf.c == 1.0 && txf.d == 0 {
            self = .left
        } else if txf.a == 1.0 && txf.b == 0 && txf.c == 0 && txf.d == 1.0 {
            self = .up
        } else if txf.a == -1.0 && txf.b == 0 && txf.c == 0 && txf.d == -1.0 {
            self = .down
        } else {
            self = .up
        }
    }
    
    var isPortrait: Bool {
        switch self {
        case .up, .down:
            return false
        case .right, .left:
            return true
        }
    }
    
    func translateAndScaleBy(width: Int, height: Int) -> (CGPoint, CGPoint) {
        var translate: CGPoint
        var scale: CGPoint
        switch self {
        case .up:
            translate = .zero
            scale = .zero
        case .right:
            translate = .init(x: -CGFloat(height)*7/8, y: 0)
            scale = .init(x: CGFloat(height)/CGFloat(width), y: CGFloat(width)/CGFloat(height))
        case .down:
            translate = .init(x: CGFloat(width), y: CGFloat(height))
            scale = .init(x: -CGFloat(width), y: -CGFloat(height))
        case .left:
            translate = .init(x: 0, y: -CGFloat(width)*9/8)
            scale = .init(x: CGFloat(height)/CGFloat(width), y: CGFloat(width)/CGFloat(height))
        }
        return (translate, scale)
    }
    
    func translateRect(width: Int, height: Int) -> CGRect {
        switch self {
        case .up, .down:
            return .init(x: 0, y: 0, width: width, height: height)
        case .right, .left:
            return .init(x: 0, y: 0, width: height, height: width)
        }
    }
    
    var rotate: Double {
        switch self {
        case .up:
            return 0
        case .right:
            return Double.pi / 2
        case .down:
            return Double.pi
        case .left:
            return Double.pi / 2 * 3
        }
    }
    
    func affineTransform(videoTrack: AVAssetTrack) -> CGAffineTransform? {
        switch self {
        case .up:
            return CGAffineTransform.identity
        case .right:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .down:
            return CGAffineTransform(rotationAngle: .pi)
        case .left:
            return CGAffineTransform(rotationAngle: .pi * 3 / 2)
        }
    }
}
