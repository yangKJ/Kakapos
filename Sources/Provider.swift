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
        let asset: AVAsset
        let assets: [AVAsset]
        let outputURL: URL
        let fileType: MovieFileType?
        
        // Used in more assets.
        var firstSegmentTransform: CGAffineTransform = .identity
        var isFirstSegmentTransformSet = false
    }
}

extension Exporter.Provider {
    
    public init(with videoURL: URL, to outputURL: URL? = nil) {
        let urlAsset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.init(with: urlAsset, to: outputURL)
    }
    
    public init(with asset: AVAsset, to outputURL: URL? = nil) {
        self.init(with: [asset], to: outputURL)
    }
    
    public init(with urls: [URL], to outputURL: URL? = nil) {
        let assets = urls.map {
            AVURLAsset(url: $0, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        }
        self.init(with: assets, to: outputURL)
    }
    
    public init(with assets: [AVAsset], to outputURL: URL? = nil) {
        self.assets = assets
        self.asset = assets[0]
        if let outputURL = outputURL {
            self.outputURL = outputURL
            self.fileType = MovieFileType.from(url: outputURL)
        } else {
            self.outputURL = Exporter.Provider.setupOutputURL()
            self.fileType = .mp4
        }
        if assets.count > 1 {
            for asset in assets {
                if !isFirstSegmentTransformSet, let videoTrack = asset.tracks(withMediaType: .video).first {
                    firstSegmentTransform = videoTrack.preferredTransform
                    isFirstSegmentTransformSet = true
                }
            }
        }
    }
    
    static func setupOutputURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let random = Int(Date().timeIntervalSince1970/2)
        let outputURL = documents.appendingPathComponent("condy_export_video_\(random).mp4")
        // Check if the file already exists then remove the previous file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        return outputURL
    }
}
