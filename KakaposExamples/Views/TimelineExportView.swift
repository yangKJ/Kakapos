//
//  TimelineExportView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI
import AVFoundation
import AVKit
import Kakapos

struct TimelineExportView: View {
    @ObservedObject var mediaStore: ExampleAppState

    @State private var player: AVPlayer?
    @State private var message = "Compile a timeline with transitions, audio mix and keyframes"
    @State private var transitionEnabled = true

    var body: some View {
        VStack(spacing: 18) {
            BoardHeaderView(board: .timeline)
            VideoPlayer(player: player)
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.08))
                .cornerRadius(8)
            Toggle("Cross Dissolve + Audio Crossfade", isOn: $transitionEnabled)
            HStack {
                Button("Compile Timeline") { compileTimeline() }
                Button("Latest Clip Timeline") { compileRecordedClipTimeline() }
                    .disabled(mediaStore.latestRecordedClip == nil)
            }
            .buttonStyle(.borderedProminent)
            Text("Latest Clip: \(mediaStore.latestRecordedClipFilename)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(message).font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        #if !os(macOS)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    private func compileTimeline() {
        guard let firstURL = Bundle.main.url(forResource: "IMG_1388", withExtension: "mp4"),
              let secondURL = Bundle.main.url(forResource: "IMG_3156", withExtension: "MOV") else {
            message = "Timeline assets missing"
            return
        }
        let timeline = KakaposSurface.timeline(renderSize: CGSize(width: 720, height: 1280), frameDuration: CMTime(value: 1, timescale: 30))
        let firstClip = ClipLayer(
            asset: AVAsset(url: firstURL),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3.2, preferredTimescale: 600)),
            layerLevel: 0,
            volume: 0.9
        )
        let secondClip = ClipLayer(
            asset: AVAsset(url: secondURL),
            timeRange: CMTimeRange(start: CMTime(seconds: 2.8, preferredTimescale: 600), duration: CMTime(seconds: 3.2, preferredTimescale: 600)),
            layerLevel: 1,
            volume: 0.75
        )
        secondClip.keyframes = [
            KeyframeAnimation(
                keyPath: "opacity",
                values: [0.25, 1.0],
                keyTimes: [secondClip.timeRange.start, secondClip.timeRange.end]
            ),
            KeyframeAnimation(
                keyPath: "translation.y",
                values: [180, 0],
                keyTimes: [secondClip.timeRange.start, secondClip.timeRange.end],
                easing: .easeOut
            ),
            KeyframeAnimation(
                keyPath: "scale",
                values: [0.82, 1.0],
                keyTimes: [secondClip.timeRange.start, secondClip.timeRange.end],
                easing: .easeOut
            )
        ]
        timeline.addLayer(firstClip)
        timeline.addLayer(secondClip)
        if transitionEnabled {
            timeline.addTransition(
                Transition(
                    timeRange: CMTimeRange(start: CMTime(seconds: 2.8, preferredTimescale: 600), duration: CMTime(seconds: 0.4, preferredTimescale: 600)),
                    sourceLayerLevel: 0,
                    destinationLayerLevel: 1
                )
            )
        }
        let compiled = timeline.compile()
        let item = AVPlayerItem(asset: compiled.composition)
        item.videoComposition = compiled.videoComposition
        item.audioMix = compiled.audioMix
        player = AVPlayer(playerItem: item)
        player?.play()
        message = "Timeline: \(compiled.summary.summaryText)"
    }

    private func compileRecordedClipTimeline() {
        guard let recordedClip = mediaStore.latestRecordedClip else {
            message = "No recorded clip available"
            return
        }
        guard let timeline = KakaposSurface.timeline(recordedClip: recordedClip) else {
            message = "Recorded clip timeline unavailable"
            return
        }
        let compiled = timeline.compile()
        let item = AVPlayerItem(asset: compiled.composition)
        item.videoComposition = compiled.videoComposition
        item.audioMix = compiled.audioMix
        player = AVPlayer(playerItem: item)
        player?.play()
        message = "Latest clip timeline: \(compiled.summary.summaryText)"
    }
}
