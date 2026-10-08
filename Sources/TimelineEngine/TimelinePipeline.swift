//
//  TimelinePipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import AVFoundation

public final class TimelinePipeline {
    public struct Summary {
        public let renderSize: CGSize
        public let frameDuration: CMTime
        public let layerCount: Int
        public let transitionCount: Int
        public let compiledSummary: TimelineCompilationSummary
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

    private var compiledSnapshot: CompiledTimelineComposition?

    public var summary: Summary {
        let compiled = currentCompilation()
        return Summary(
            renderSize: composition.renderSize,
            frameDuration: composition.frameDuration,
            layerCount: composition.layers.count,
            transitionCount: composition.transitions.count,
            compiledSummary: compiled.summary,
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

    public convenience init?(
        recordedClip: RecordedClip,
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        startTime: CMTime = .zero,
        sourceTimeRange: CMTimeRange? = nil,
        layerLevel: Int = 0
    ) {
        guard let layer = ClipLayer(
            recordedClip: recordedClip,
            startTime: startTime,
            sourceTimeRange: sourceTimeRange,
            layerLevel: layerLevel
        ) else {
            return nil
        }
        self.init(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: [layer]
        )
    }

    public func addLayer(_ layer: TimelineLayer) {
        composition.addLayer(layer)
        compiledSnapshot = nil
    }

    public func addTransition(_ transition: Transition) {
        composition.addTransition(transition)
        compiledSnapshot = nil
    }

    /// 每次调用显式生成新的编辑快照；已有任务继续消费其原快照。
    public func compile(exportProfile: VideoExportProfile = .legacyCompatible) -> CompiledTimelineComposition {
        var compiled = composition.compile()
        compiled.exportProfile = exportProfile
        if exportProfile.colorPolicy.isHDR {
            compiled.videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            compiled.videoComposition.colorTransferFunction = exportProfile.colorPolicy == .hdrHLG ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_SMPTE_ST_2084_PQ
            compiled.videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }
        compiledSnapshot = compiled
        return compiled
    }

    private func currentCompilation() -> CompiledTimelineComposition {
        compiledSnapshot ?? compile()
    }

    public func makeAssetSources(
        callbackQueue: DispatchQueue = .main,
        audioOutputSettings: [String: Any]? = nil
    ) -> [AssetSource] {
        currentCompilation().makeAssetSources(
            callbackQueue: callbackQueue,
            audioOutputSettings: audioOutputSettings
        )
    }

    public func makeImageSource(
        callbackQueue: DispatchQueue = .main
    ) -> ImageSource? {
        currentCompilation().makeImageSource(callbackQueue: callbackQueue)
    }

    public func makeProcessorChain() -> MediaProcessorChain {
        currentCompilation().makeProcessorChain()
    }

    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        currentCompilation().makePlayerItem()
    }

    public func makeExportJob(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        videoFrameProcessingTimeout: TimeInterval? = nil
    ) -> ReaderWriterExportJob {
        currentCompilation().makeExportJob(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout
        )
    }

    public func makeExportTask(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        videoFrameProcessingTimeout: TimeInterval? = nil
    ) -> TimelineExportTask {
        TimelineExportTask(
            compiledComposition: currentCompilation(),
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout
        )
    }

    @discardableResult
    public func export(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        shouldOptimizeForNetworkUse: Bool = true,
        metadata: [AVMetadataItem] = [],
        videoProcessors: [FrameProcessor] = [],
        videoFrameProcessingTimeout: TimeInterval? = nil,
        complete: @escaping (Result<URL, VideoX.Error>) -> Void,
        progress: ((Float) -> Void)? = nil,
        progressInfo: ((ReaderWriterExportJob.ProgressInfo) -> Void)? = nil
    ) -> TimelineExportTask {
        let exportTask = makeExportTask(
            outputURL: outputURL,
            fileType: fileType,
            shouldOptimizeForNetworkUse: shouldOptimizeForNetworkUse,
            metadata: metadata,
            videoProcessors: videoProcessors,
            videoFrameProcessingTimeout: videoFrameProcessingTimeout
        )
        exportTask.start(
            complete: complete,
            progress: progress,
            progressInfo: progressInfo
        )
        return exportTask
    }
}

#if canImport(UIKit) || os(macOS)
public extension TimelinePipeline {
    @MainActor
    func makePreviewPipeline(
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline {
        PreviewPipeline(
            player: AVPlayer(playerItem: makePlayerItem()),
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors.isEmpty ? currentCompilation().timelineProcessors : processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }
}
#endif

#if canImport(UIKit)
public extension CompiledTimelineComposition {
    @MainActor
    func makePreviewSession(surface: VideoPreviewSurface, preferredFramesPerSecond: Int = 30) throws -> VideoPreviewSession {
        let session = VideoPreviewSession(player: AVPlayer(playerItem: makePlayerItem()), surface: surface,
            configuration: VideoPreviewConfiguration(preferredFramesPerSecond: preferredFramesPerSecond, colorPolicy: exportProfile.colorPolicy))
        if !renderPlan.processorSegments.isEmpty {
            let snapshot = self
            let plan = FrameProcessingPlan(identity: .init(identifier: "kakapos.timeline", revision: UUID().uuidString), makeProcessors: { snapshot.timelineProcessors })
            _ = try session.setMode(.processed(plan))
        }
        return session
    }
}
#endif
