//
//  Command.swift
//  VideoBox
//
//  Created by Condy on 2022/12/20.
//

import Foundation
@_exported import AVFoundation

public typealias Tracks = (videoTrack: AVMutableCompositionTrack, audioTrack: AVMutableCompositionTrack?)

public protocol Command {
    func execute(export: AVAssetExportSession, tracks: Tracks, videoComposition: AVMutableVideoComposition)
}
