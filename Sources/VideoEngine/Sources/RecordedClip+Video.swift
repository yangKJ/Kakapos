//
//  RecordedClip+Video.swift
//  Kakapos
//

import AVFoundation
import KakaposMediaCore

public extension RecordedClip {
    var fileExists: Bool {
        guard let outputURL else { return false }
        return FileManager.default.fileExists(atPath: outputURL.path)
    }

    var asset: AVAsset? {
        outputURL.map(AVAsset.init(url:))
    }

    var frameRate: Float {
        asset?.tracks(withMediaType: .video).first?.nominalFrameRate ?? 0
    }

    func generatedPreviewImage(at time: CMTime = .zero) -> CGImage? {
        guard let asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        return try? generator.copyCGImage(at: time, actualTime: nil)
    }

    func generatedLastFrameImage() -> CGImage? {
        guard duration.isNumeric, duration > .zero else {
            return generatedPreviewImage()
        }
        return generatedPreviewImage(at: duration)
    }

    func makeAssetSource(
        timeRange: CMTimeRange? = nil,
        videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ],
        audioOutputSettings: [String: Any]? = nil,
        callbackQueue: DispatchQueue = .main
    ) -> AssetSource? {
        AssetSource(
            recordedClip: self,
            timeRange: timeRange,
            videoOutputSettings: videoOutputSettings,
            audioOutputSettings: audioOutputSettings,
            callbackQueue: callbackQueue
        )
    }
}

#if canImport(UIKit) || os(macOS)
public extension MediaPipeline {
    convenience init(
        player: AVPlayer,
        processors: [FrameProcessor] = [],
        sinks: [MediaSink] = []
    ) {
        self.init(source: PlayerFrameSource(player: player), processors: processors, sinks: sinks)
    }
}

public extension RecordedClip {
    @MainActor
    func makePlayerItem() -> AVPlayerItem? {
        guard let asset else { return nil }
        return AVPlayerItem(asset: asset)
    }

    @MainActor
    func makePlayerFrameSource(preferredFramesPerSecond: Int = 30) -> PlayerFrameSource? {
        PlayerFrameSource(recordedClip: self, preferredFramesPerSecond: preferredFramesPerSecond)
    }

    func makePreviewPipeline(
        preferredFramesPerSecond: Int = 30,
        processors: [FrameProcessor] = [],
        callbackQueue: DispatchQueue = .main,
        handler: @escaping PreviewSink.Handler
    ) -> PreviewPipeline? {
        PreviewPipeline(
            recordedClip: self,
            preferredFramesPerSecond: preferredFramesPerSecond,
            processors: processors,
            callbackQueue: callbackQueue,
            handler: handler
        )
    }
}
#endif
