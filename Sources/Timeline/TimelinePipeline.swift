//
//  TimelinePipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class TimelinePipeline {
    public struct Summary {
        public let renderSize: CGSize
        public let frameDuration: CMTime
        public let layerCount: Int
        public let transitionCount: Int
        public let compiledSummaryText: String

        public var summaryText: String {
            let sizeText = "\(Int(renderSize.width))x\(Int(renderSize.height))"
            let frameRateText = frameDuration.timescale > 0
                ? "\(frameDuration.timescale)fps"
                : "fps n/a"
            return "size \(sizeText) · frame \(frameRateText) · layers \(layerCount) · transitions \(transitionCount) · \(compiledSummaryText)"
        }
    }

    public let composition: TimelineComposition

    public var layers: [TimelineLayer] {
        get { composition.layers }
        set { composition.layers = newValue }
    }

    public var transitions: [Transition] {
        get { composition.transitions }
        set { composition.transitions = newValue }
    }

    public var renderSize: CGSize {
        composition.renderSize
    }

    public var frameDuration: CMTime {
        composition.frameDuration
    }

    public var summary: Summary {
        let compiled = compile()
        return Summary(
            renderSize: composition.renderSize,
            frameDuration: composition.frameDuration,
            layerCount: composition.layers.count,
            transitionCount: composition.transitions.count,
            compiledSummaryText: compiled.summary.summaryText
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = []
    ) {
        self.composition = TimelineComposition(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        )
    }

    public init(composition: TimelineComposition) {
        self.composition = composition
    }

    public func addLayer(_ layer: TimelineLayer) {
        composition.addLayer(layer)
    }

    public func addTransition(_ transition: Transition) {
        composition.addTransition(transition)
    }

    public func compile() -> CompiledTimelineComposition {
        composition.compile()
    }

    public func makeAssetSources(
        callbackQueue: DispatchQueue = .main,
        audioOutputSettings: [String: Any]? = nil
    ) -> [AssetSource] {
        compile().makeAssetSources(
            callbackQueue: callbackQueue,
            audioOutputSettings: audioOutputSettings
        )
    }

    public func makeImageSource(
        callbackQueue: DispatchQueue = .main
    ) -> ImageSource? {
        compile().makeImageSource(callbackQueue: callbackQueue)
    }

    public func makeProcessorChain() -> MediaProcessorChain {
        compile().makeProcessorChain()
    }

    public func makePlayerItem() -> AVPlayerItem {
        compile().makePlayerItem()
    }

    public func makeExportJob(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = []
    ) -> ReaderWriterExportJob {
        compile().makeExportJob(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    public func makeExportTask(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = []
    ) -> TimelineExportTask {
        TimelineExportTask(
            compiledComposition: compile(),
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
    }

    @discardableResult
    public func export(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        complete: @escaping (Result<URL, VideoX.Error>) -> Void,
        progress: ((Float) -> Void)? = nil,
        progressInfo: ((ReaderWriterExportJob.ProgressInfo) -> Void)? = nil
    ) -> TimelineExportTask {
        let exportTask = makeExportTask(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors
        )
        exportTask.start(
            complete: complete,
            progress: progress,
            progressInfo: progressInfo
        )
        return exportTask
    }
}

#if canImport(UIKit)
public extension TimelinePipeline {
    func makePreviewPipeline(
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        PreviewPipeline(
            player: AVPlayer(playerItem: makePlayerItem()),
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }
}
#endif
