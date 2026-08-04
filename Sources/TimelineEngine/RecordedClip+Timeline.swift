//
//  RecordedClip+Timeline.swift
//  Kakapos
//

import AVFoundation
import KakaposMediaCore
import KakaposVideo

public extension RecordedClip {
    func makeTimelinePipeline(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> TimelinePipeline? {
        TimelinePipeline(
            recordedClip: self,
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )
    }

    func makeExportJob(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> ReaderWriterExportJob? {
        makeTimelinePipeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )?.makeExportJob(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    func makeExportTask(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) -> TimelineExportTask? {
        makeTimelinePipeline(
            renderSize: renderSize,
            frameDuration: frameDuration,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        )?.makeExportTask(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }
}
