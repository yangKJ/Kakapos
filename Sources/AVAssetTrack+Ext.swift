//
//  AVAssetTrack+Ext.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation
import AVFoundation

extension KakaposWrapper where Base: AVAssetTrack {
    
    public var videoOrientation: VideoOrientation {
        VideoOrientation.getVideoOrientation(with: base)
    }
}
