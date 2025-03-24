//
//  Provider.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import Foundation
import AVFoundation

extension VideoX {
    /// Setup input source and output link URL.
    public struct Provider {
        public let asset: AVAsset
        public let outputURL: URL
        public let duration: CMTime
        public let videoTracks: [AVAssetTrack]
        public let audioTracks: [AVAssetTrack]
        public let orientation: VideoOrientation
        
        let fileType: MovieFileType?
    }
}

extension VideoX.Provider {
    
    public var videoTrack: AVAssetTrack? {
        videoTracks.first
    }
    
    public init(with videoURL: URL, to outputURL: URL? = nil) {
        let urlAsset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.init(with: urlAsset, to: outputURL)
    }
    
    public init(with asset: AVAsset, to outputURL: URL? = nil) {
        self.asset = asset
        self.videoTracks = asset.tracks(withMediaType: .video)
        self.audioTracks = asset.tracks(withMediaType: .audio)
        if let videoTrack = self.videoTracks.first {
            // Make sure source's duration not beyond video track's duration.
            self.duration = videoTrack.timeRange.duration
            self.orientation = videoTrack.kaka.videoOrientation
        } else {
            self.duration = asset.duration
            self.orientation = VideoOrientation.up
        }
        
        if let outputURL = outputURL {
            self.outputURL = outputURL
            self.fileType = MovieFileType.from(url: outputURL)
        } else {
            let fileType_: MovieFileType = .mp4
            self.fileType = fileType_
            self.outputURL = try! FileManager.default.kaka.createURL(prefix: "condy_export_video", pathExtension: fileType_.pathExtension)
        }
    }
    
    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        return asset.tracks(withMediaType: type)
    }
}
