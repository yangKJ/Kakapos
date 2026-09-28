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
    
    static func getVideoOrientation(with track: AVAssetTrack) -> VideoOrientation {
        let size = track.naturalSize
        let txf = track.preferredTransform
        if size.width == txf.tx && size.height == txf.ty {
            return VideoOrientation.up
        } else if txf.tx == 0 && txf.ty == 0 {
            return VideoOrientation.right
        } else if txf.tx == 0 && txf.ty == size.width {
            return VideoOrientation.down
        } else {
            return VideoOrientation.left
        }
    }
}
