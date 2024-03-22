//
//  MovieMerger.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation
import AVFoundation

public struct MovieMerger {
    
    let assets: [AVAsset]
    let outputURL: URL
    let fileType: MovieFileType?
    
    var firstSegmentTransform: CGAffineTransform = .identity
    var isFirstSegmentTransformSet = false
    
    public init(with urls: [URL], to outputURL: URL? = nil) {
        let assets = urls.map {
            AVURLAsset(url: $0, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        }
        self.init(with: assets, to: outputURL)
    }
    
    public init(with assets: [AVAsset], to outputURL: URL? = nil) {
        self.assets = assets
        if let outputURL = outputURL {
            self.outputURL = outputURL
            self.fileType = MovieFileType.from(url: outputURL)
        } else {
            self.fileType = .mp4
            self.outputURL = try! FileManager.default.kaka.createURL(prefix: "condy_merger_video")
        }
        for asset in assets {
            if !isFirstSegmentTransformSet, let videoTrack = asset.tracks(withMediaType: .video).first {
                firstSegmentTransform = videoTrack.preferredTransform
                isFirstSegmentTransformSet = true
            }
        }
    }
    
    public func merge(options: [Exporter.Option: Any] = [:], complete: @escaping ExportComplete, progress: ((Float) -> Void)? = nil) {
        guard let avFileType = self.fileType?.avFileType else {
            complete(.failure(Exporter.Error.unsupportedFileType))
            return
        }
        
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        for asset in self.assets {
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                try composition.insertTimeRange(range, of: asset, at: current)
                current = CMTimeAdd(current, asset.duration)
            } catch {
                complete(.failure(Exporter.Error.error(error)))
                return
            }
        }
        let videoTrack = composition.tracks(withMediaType: .video).first
        if self.isFirstSegmentTransformSet {
            videoTrack?.preferredTransform = self.firstSegmentTransform
        }
        
        let presetName = Exporter.Option.setupPresetName(options: options)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            complete(.failure(Exporter.Error.exportSessionEmpty))
            return
        }
        exportSession.outputURL = self.outputURL
        exportSession.outputFileType = avFileType
        if let range = Exporter.Option.setupExportSessionTimeRange(duration: composition.duration, options: options) {
            exportSession.timeRange = range
        } else {
            exportSession.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        }
        exportSession.shouldOptimizeForNetworkUse = Exporter.Option.setupOptimizeForNetworkUse(options: options)
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                progress?(1.0)
                complete(.success(self.outputURL))
            case .cancelled:
                progress?(exportSession.progress)
                complete(.failure(Exporter.Error.exportCancelled))
            case .failed:
                progress?(exportSession.progress)
                complete(.failure(Exporter.Error.toError(exportSession.error)))
            default:
                progress?(exportSession.progress)
                complete(.failure(Exporter.Error.exportAsynchronously(exportSession.status)))
                break
            }
        }
    }
}
