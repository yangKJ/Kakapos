//
//  TimelineComposition.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics

public struct CompiledTimelineComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
}

public final class TimelineComposition {
    public var renderSize: CGSize
    public var frameDuration: CMTime
    public var layers: [TimelineLayer]

    public init(renderSize: CGSize = CGSize(width: 720, height: 1280), frameDuration: CMTime = CMTime(value: 1, timescale: 30), layers: [TimelineLayer] = []) {
        self.renderSize = renderSize
        self.frameDuration = frameDuration
        self.layers = layers
    }

    public func addLayer(_ layer: TimelineLayer) {
        layers.append(layer)
    }

    public func compile() -> CompiledTimelineComposition {
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        let audioMix = AVMutableAudioMix()
        var audioParameters: [AVMutableAudioMixInputParameters] = []

        for layer in layers.sorted(by: { $0.timeRange.start < $1.timeRange.start }) {
            if let clip = layer as? ClipLayer {
                addClipLayer(clip, to: composition, audioParameters: &audioParameters)
            } else if let audio = layer as? AudioLayer {
                addAudioLayer(audio, to: composition, audioParameters: &audioParameters)
            }
        }

        audioMix.inputParameters = audioParameters
        return CompiledTimelineComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    private func addClipLayer(_ layer: ClipLayer, to composition: AVMutableComposition, audioParameters: inout [AVMutableAudioMixInputParameters]) {
        guard let videoTrack = layer.asset.tracks(withMediaType: .video).first else { return }
        let sourceRange = layer.sourceTimeRange ?? videoTrack.timeRange
        if let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compositionTrack.insertTimeRange(sourceRange, of: videoTrack, at: layer.timeRange.start)
            compositionTrack.preferredTransform = videoTrack.preferredTransform
        }
        if let audioTrack = layer.asset.tracks(withMediaType: .audio).first,
           let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compositionTrack.insertTimeRange(sourceRange, of: audioTrack, at: layer.timeRange.start)
            let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
            layer.audioRamps.forEach { ramp in
                parameters.setVolumeRamp(fromStartVolume: ramp.startVolume, toEndVolume: ramp.endVolume, timeRange: ramp.timeRange)
            }
            audioParameters.append(parameters)
        }
    }

    private func addAudioLayer(_ layer: AudioLayer, to composition: AVMutableComposition, audioParameters: inout [AVMutableAudioMixInputParameters]) {
        guard let audioTrack = layer.asset.tracks(withMediaType: .audio).first,
              let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        let sourceRange = layer.sourceTimeRange ?? audioTrack.timeRange
        try? compositionTrack.insertTimeRange(sourceRange, of: audioTrack, at: layer.timeRange.start)
        let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        layer.audioRamps.forEach { ramp in
            parameters.setVolumeRamp(fromStartVolume: ramp.startVolume, toEndVolume: ramp.endVolume, timeRange: ramp.timeRange)
        }
        audioParameters.append(parameters)
    }
}
