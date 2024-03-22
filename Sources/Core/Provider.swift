//
//  Provider.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import Foundation
import AVFoundation

extension Exporter {
    /// Setup input source and output link URL.
    public struct Provider {
        public let asset: AVAsset
        public let outputURL: URL
        public let duration: CMTime
        public let videoTracks: [AVAssetTrack]
        public let audioTracks: [AVAssetTrack]
        
        let fileType: MovieFileType?
    }
}

extension Exporter.Provider {
    
    public init(with videoURL: URL, to outputURL: URL? = nil) {
        let urlAsset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.init(with: urlAsset, to: outputURL)
    }
    
    public init(with asset: AVAsset, to outputURL: URL? = nil) {
        self.asset = asset
        self.videoTracks = asset.tracks(withMediaType: .video)
        self.audioTracks = asset.tracks(withMediaType: .audio)
        if let videoTrack = self.videoTracks.first {
            // Make sure source's duration not beyond video track's duration
            self.duration = videoTrack.timeRange.duration
        } else {
            self.duration = asset.duration
        }
        
        if let outputURL = outputURL {
            self.outputURL = outputURL
            self.fileType = MovieFileType.from(url: outputURL)
        } else {
            self.fileType = .mp4
            self.outputURL = try! FileManager.default.kaka.createURL(prefix: "condy_export_video")
        }
    }
}
