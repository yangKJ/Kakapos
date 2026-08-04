//
//  PlayerPreviewView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI
import AVFoundation
import Harbeth

struct PlayerPreviewView: View {
    @ObservedObject var mediaStore: ExampleAppState

    @State private var player: AVPlayer?
    @State private var previewImage: CGImage?
    @State private var frameCount = 0
    @State private var currentTimeText = "0.00s"
    @State private var message = "Tap Start to pull player frames into PreviewSink"
    @State private var previewStateText = "idle"
    @State private var previewGeneration: Int64 = 0
    #if canImport(UIKit) || os(macOS)
    @State private var previewPipeline: PreviewPipeline?
    #endif

    var body: some View {
        VStack(spacing: 18) {
            BoardHeaderView(board: .preview)
            Group {
                if let previewImage {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.08))
                        Text("Processed preview will appear here")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Frames: \(frameCount)")
                .font(.headline)
            Text("Time: \(currentTimeText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("State: \(previewStateText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            #if canImport(UIKit) || os(macOS)
            Text(previewPipeline?.playerSource?.summaryText ?? "state idle · generation 0 · frame 0 · lastFrame no · seekTarget no · fps 30")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(previewPipeline?.previewSink.summaryText ?? "state idle · frame n/a · image n/a · pending no")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(previewPipeline?.summary.summaryText ?? "source unavailable · processors 0 · sinks 0 · state idle")
                .font(.footnote)
                .foregroundColor(.secondary)
            #else
            Text("state idle · generation 0 · frame 0 · lastFrame no · seekTarget no · fps 30")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("state idle · frame n/a · image n/a · pending no")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("source unavailable · processors 0 · sinks 0 · state idle")
                .font(.footnote)
                .foregroundColor(.secondary)
            #endif

            HStack {
                Button("Start") { startPreview() }
                Button("Latest Clip") { startRecordedClipPreview() }
                    .disabled(mediaStore.latestRecordedClip == nil)
                Button("Pause") { pausePreview() }
                Button("Resume") { resumePreview() }
                Button("Restart") { restartPreview() }
                Button("Seek 2s") { seekPreview(to: CMTime(seconds: 2, preferredTimescale: 600)) }
                Button("Stop") { stopPreview() }
            }
            .buttonStyle(.borderedProminent)

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

    private func startPreview() {
        guard let videoURL = Bundle.main.url(forResource: "IMG_1388", withExtension: "mp4") else {
            message = "Input video missing"
            return
        }
        let player = AVPlayer(url: videoURL)
        self.player = player
        frameCount = 0
        previewImage = nil
        currentTimeText = "0.00s"
        previewStateText = "starting"
        previewGeneration = 0
        #if canImport(UIKit) || os(macOS)
        let pipeline = KakaposSurface.preview(
            player: player,
            processors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.1), C7Exposure(exposure: 0.15)])]
        ) { image, metadata in
            let generation = metadata.userInfo[PlayerFrameSource.MetadataKey.generation] as? Int64 ?? 0
            guard generation >= previewGeneration else { return }
            previewGeneration = generation
            previewImage = image
            frameCount += 1
            currentTimeText = String(format: "%.2fs", metadata.presentationTime.seconds)
            previewStateText = metadata.userInfo[PlayerFrameSource.MetadataKey.playbackState] as? String ?? "running"
        }
        self.previewPipeline = pipeline
        pipeline.start()
        player.play()
        message = "Previewing processed player frames"
        previewStateText = "running"
        #else
        message = "PlayerFrameSource is available in UIKit environments"
        #endif
    }

    private func startRecordedClipPreview() {
        #if canImport(UIKit) || os(macOS)
        guard let recordedClip = mediaStore.latestRecordedClip else {
            message = "No recorded clip available"
            return
        }
        frameCount = 0
        previewImage = nil
        currentTimeText = "0.00s"
        previewStateText = "starting"
        previewGeneration = 0
        let pipeline = KakaposSurface.preview(
            recordedClip: recordedClip,
            processors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.08), C7Exposure(exposure: 0.1)])]
        ) { image, metadata in
            previewImage = image
            frameCount += 1
            currentTimeText = String(format: "%.2fs", metadata.presentationTime.seconds)
            previewStateText = "clip-running"
        }
        guard let pipeline else {
            message = "Recorded clip preview unavailable"
            previewStateText = "failed"
            return
        }
        self.player = nil
        self.previewPipeline = pipeline
        pipeline.start()
        message = "Previewing latest recorded clip"
        #endif
    }

    private func pausePreview() {
        player?.pause()
        #if canImport(UIKit) || os(macOS)
        previewPipeline?.pause()
        #endif
        previewStateText = "paused"
        message = "Preview paused"
    }

    private func resumePreview() {
        #if canImport(UIKit) || os(macOS)
        previewPipeline?.resume()
        #endif
        player?.play()
        previewStateText = "running"
        message = "Preview resumed"
    }

    private func restartPreview() {
        seekPreview(to: .zero, message: "Preview restarted from zero")
    }

    private func seekPreview(to time: CMTime, message: String = "Preview seeked") {
        #if canImport(UIKit) || os(macOS)
        previewPipeline?.seek(to: time) { finished in
            guard finished else { return }
            DispatchQueue.main.async {
                self.player?.play()
                self.previewStateText = "running"
                self.currentTimeText = String(format: "%.2fs", time.seconds)
                self.message = message
            }
        }
        if previewPipeline == nil {
            player?.seek(to: time)
            player?.play()
            currentTimeText = String(format: "%.2fs", time.seconds)
            previewStateText = "running"
            self.message = message
        }
        #else
        player?.seek(to: time)
        player?.play()
        currentTimeText = String(format: "%.2fs", time.seconds)
        previewStateText = "running"
        self.message = message
        #endif
    }

    private func stopPreview() {
        player?.pause()
        #if canImport(UIKit) || os(macOS)
        previewPipeline?.stop()
        previewPipeline = nil
        #endif
        previewImage = nil
        previewStateText = "stopped"
        previewGeneration = 0
        message = "Stopped"
    }
}
