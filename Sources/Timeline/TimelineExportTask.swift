//
//  TimelineExportTask.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class TimelineExportTask {
    public struct Summary {
        public let renderSize: CGSize
        public let frameDuration: CMTime
        public let layerCount: Int
        public let transitionCount: Int
        public let processorCount: Int
        public let exportStatus: ReaderWriterExportJob.Status
        public let lastProgressInfo: ReaderWriterExportJob.ProgressInfo?
        public let lastErrorDescription: String?

        public var summaryText: String {
            let sizeText = "\(Int(renderSize.width))x\(Int(renderSize.height))"
            let frameRateText = frameDuration.timescale > 0
                ? "\(frameDuration.timescale)fps"
                : "fps n/a"
            var text = "size \(sizeText) · frame \(frameRateText) · layers \(layerCount) · transitions \(transitionCount) · processors \(processorCount) · export \(exportStatus)"
            if let lastProgressInfo {
                text += " · progress \(Int((lastProgressInfo.overallFractionCompleted * 100).rounded()))%"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }
    }

    public let compiledComposition: CompiledTimelineComposition
    public let readerWriterJob: ReaderWriterExportJob
    public private(set) var progressFraction: Float?

    public var status: ReaderWriterExportJob.Status {
        readerWriterJob.status
    }

    public var progressInfo: ReaderWriterExportJob.ProgressInfo? {
        readerWriterJob.lastProgressInfo
    }

    public var summary: Summary {
        Summary(
            renderSize: compiledComposition.summary.renderSize,
            frameDuration: compiledComposition.summary.frameDuration,
            layerCount: compiledComposition.summary.videoLayerCount
                + compiledComposition.summary.imageLayerCount
                + compiledComposition.summary.textLayerCount
                + compiledComposition.summary.effectLayerCount,
            transitionCount: compiledComposition.summary.transitionCount,
            processorCount: compiledComposition.summary.processorCount,
            exportStatus: readerWriterJob.status,
            lastProgressInfo: readerWriterJob.lastProgressInfo,
            lastErrorDescription: readerWriterJob.lastErrorDescription
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(
        compiledComposition: CompiledTimelineComposition,
        readerWriterJob: ReaderWriterExportJob
    ) {
        self.compiledComposition = compiledComposition
        self.readerWriterJob = readerWriterJob
    }

    public convenience init(
        compiledComposition: CompiledTimelineComposition,
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = []
    ) {
        self.init(
            compiledComposition: compiledComposition,
            readerWriterJob: compiledComposition.makeExportJob(
                outputURL: outputURL,
                fileType: fileType,
                shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
                metadata: metadata,
                videoProcessors: videoProcessors
            )
        )
    }

    public func start(
        complete: @escaping (Result<URL, VideoX.Error>) -> Void,
        progress: ((Float) -> Void)? = nil,
        progressInfo: ((ReaderWriterExportJob.ProgressInfo) -> Void)? = nil
    ) {
        readerWriterJob.progressHandler = { info in
            self.progressFraction = Float(info.overallFractionCompleted)
            progress?(Float(info.overallFractionCompleted))
            progressInfo?(info)
        }
        readerWriterJob.export { result in
            switch result {
            case .success(let outputURL):
                if let lastProgressInfo = self.readerWriterJob.lastProgressInfo {
                    self.progressFraction = Float(lastProgressInfo.overallFractionCompleted)
                    progress?(Float(lastProgressInfo.overallFractionCompleted))
                }
                complete(.success(outputURL))
            case .failure(let error):
                complete(.failure(VideoX.Error.toError(error)))
            }
        }
    }

    public func pause() {
        readerWriterJob.pause()
    }

    public func resume() {
        readerWriterJob.resume()
    }

    public func cancel() {
        readerWriterJob.cancel()
    }
}
