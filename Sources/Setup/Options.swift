//
//  Options.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import Foundation
import AVFoundation
import CoreVideo

extension VideoX {
    
    /// VideoX with options.
    public struct Option : Hashable, Equatable, RawRepresentable, @unchecked Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        public func has(with options: [VideoX.Option: Any]) -> Any? {
            guard options.keys.contains(where: { $0 == self }) else {
                return nil
            }
            return options[self]
        }
    }
}

extension VideoX.Option {
    
    /// Indicates that the output file should be optimized for network use.
    public static let OptimizeForNetworkUse: VideoX.Option = .init(rawValue: 1 << 0)
    
    /// These export options can be used to produce movie files with video size appropriate to the device.
    public static let ExportSessionPresetName: VideoX.Option = .init(rawValue: 1 << 1)
    
    /// Indicates the interval which the video composition, when enabled, should render composed video frames. Default 30 frame.
    public static let VideoCompositionFrameDuration: VideoX.Option = .init(rawValue: 1 << 2)
    
    /// Indicates the size at which the video composition, when enabled, should render.
    /// If not set, the value is the size of the composition's first video track. Set to CGSizeZero to revert to default behavior.
    public static let VideoCompositionRenderSize: VideoX.Option = .init(rawValue: 1 << 3)
    
    /// If NO, indicates that post-processing should be skipped for the duration of this instruction.  YES by default.
    /// See +[AVVideoCompositionCoreAnimationTool videoCompositionToolWithPostProcessingAsVideoLayer:inLayer:].
    public static let VideoCompositionInstructionEnablePostProcessing: VideoX.Option = .init(rawValue: 1 << 4)
    
    /// If YES, rendering a frame from the same source buffers and the same composition instruction at 2 different compositionTime may yield different output frames.
    /// If NO, 2 such compositions would yield the same frame.
    /// The media pipeline may be able to avoid some duplicate processing when containsTweening is NO
    public static let VideoCompositionInstructionContainsTweening: VideoX.Option = .init(rawValue: 1 << 5)
    
    /// Provides an array of instances of AVVideoCompositionLayerInstruction that specify how video frames from source tracks should be layered and composed.
    /// Tracks are layered in the composition according to the top-to-bottom order of the layerInstructions array;
    /// the track with trackID of the first instruction in the array will be layered on top, with the track with the trackID of the second instruction immediately underneath, etc.
    /// If this key is nil, the output will be a fill of the background color.
    public static let VideoCompositionInstructionLayerInstructions: VideoX.Option = .init(rawValue: 1 << 6)
    
    /// Specifies a time range to be exported from the source.  meaning that the full duration of the asset will be exported.
    /// Use the `TimeRangeType`, The default timeRange of an export session is kCMTimeZero..kCMTimePositiveInfinity.
    /// See: https://github.com/yangKJ/Kakapos/blob/master/Sources/TimeRangeType.swift
    public static let ExportSessionTimeRange: VideoX.Option = .init(rawValue: 1 << 7)
    
    /// Set speed the scale at which the video composition should render.
    public static let VideoCompositionRenderScale: VideoX.Option = .init(rawValue: 1 << 8)
}

extension VideoX.Option {
    
    static func setupPresetName(options: [VideoX.Option: Any]) -> String {
        guard let value = VideoX.Option.ExportSessionPresetName.has(with: options) as? String else {
            return AVAssetExportPresetHighestQuality
        }
        if !AVAssetExportSession.allExportPresets().contains(value) {
            return AVAssetExportPresetMediumQuality
        }
        return value
    }
    
    static func setupVideoRenderSize(_ videoTracks: [AVAssetTrack], asset: AVAsset, options: [VideoX.Option: Any]) -> CGSize {
        if let value = VideoX.Option.VideoCompositionRenderSize.has(with: options) as? CGSize {
            return value
        }
        /// AVMutableVideoComposition's renderSize property is buggy with some assets.
        /// Calculate the renderSize here based on the documentation of `AVMutableVideoComposition(propertiesOf:)`
        if let composition = asset as? AVComposition {
            return composition.naturalSize
        } else {
            var renderSize: CGSize = .zero
            for videoTrack in videoTracks {
                let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                renderSize.width  = max(renderSize.width, abs(size.width))
                renderSize.height = max(renderSize.height, abs(size.height))
            }
            return renderSize
        }
    }
    
    static func setupOptimizeForNetworkUse(options: [VideoX.Option: Any]) -> Bool {
        if let value = VideoX.Option.OptimizeForNetworkUse.has(with: options) as? Bool {
            return value
        }
        return true
    }
    
    static func setupExportSessionTimeRange(duration: CMTime, options: [VideoX.Option: Any]) -> CMTimeRange? {
        guard let value = VideoX.Option.ExportSessionTimeRange.has(with: options) as? TimeRangeType else {
            return nil
        }
        //duration = try await asset.load(.duration)
        return value.timeRange(duration: duration)
    }
    
    static func setupExportSessionMinTime(options: [VideoX.Option: Any]) -> CGFloat {
        guard let value = VideoX.Option.ExportSessionTimeRange.has(with: options) as? TimeRangeType else {
            return 0.0
        }
        return value.minTime()
    }
    
    static func setupRenderScale(options: [VideoX.Option: Any]) -> Float {
        guard let value = VideoX.Option.VideoCompositionRenderScale.has(with: options) as? Float else {
            return 1.0
        }
        return value
    }
    
    static func setupVideoFrameDuration(options: [VideoX.Option: Any]) -> CMTime {
        guard let value = VideoX.Option.VideoCompositionFrameDuration.has(with: options) as? CMTime else {
            return CMTimeMake(value: 1, timescale: 30)
        }
        return value
    }
}
