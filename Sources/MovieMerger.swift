//
//  MovieMerger.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation
import AVFoundation

public struct MovieMerger {
    
    let provider: Exporter.Provider
    
    /// Craate exporter.
    /// - Parameter provider: Configure export information.
    public init(provider: Exporter.Provider) {
        self.provider = provider
    }
    
    public func merge(options: [Exporter.Option: Any] = [:], complete: @escaping ExportComplete, progress: ((Float) -> Void)? = nil) {
        guard let avFileType = provider.fileType?.avFileType else {
            complete(.failure(Exporter.Error.unsupportedFileType))
            return
        }
        
        let composition = AVMutableComposition()
        var current: CMTime = .zero
        for asset in provider.assets {
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
        if provider.isFirstSegmentTransformSet {
            videoTrack?.preferredTransform = provider.firstSegmentTransform
        }
        
        let presetName = Exporter.Option.setupPresetName(options: options)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            complete(.failure(Exporter.Error.exportSessionEmpty))
            return
        }
        exportSession.outputURL = provider.outputURL
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
                complete(.success(provider.outputURL))
            case .cancelled:
                progress?(exportSession.progress)
                complete(.failure(Exporter.Error.exportCancelled))
            case .failed:
                progress?(exportSession.progress)
                if let error = exportSession.error {
                    complete(.failure(Exporter.Error.error(error)))
                } else {
                    complete(.failure(Exporter.Error.unknown))
                }
            default:
                progress?(exportSession.progress)
                complete(.failure(Exporter.Error.exportAsynchronously(exportSession.status)))
                break
            }
        }
    }
}
