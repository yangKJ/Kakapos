//
//  ContentView.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import SwiftUI
import AVFoundation
import AVKit
import Harbeth
import Photos

struct ContentView: View {
    var body: some View {
        TabView {
            OfflineExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            PlayerPreviewView()
                .tabItem { Label("Preview", systemImage: "play.rectangle") }
            CameraRecordView()
                .tabItem { Label("Record", systemImage: "camera") }
            TimelineExportView()
                .tabItem { Label("Timeline", systemImage: "timeline.selection") }
        }
    }
}

private struct OfflineExportView: View {
    @State private var player: AVPlayer?
    @State private var outputURL: URL?
    @State private var isProcessing = false
    @State private var progress: Float = 0
    @State private var message = "Ready"
    @State private var selectedRotation: RotationAngle = .angle0

    var body: some View {
        VStack(spacing: 18) {
            VideoPlayer(player: player)
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.08))
                .cornerRadius(8)

            Picker("Rotation", selection: $selectedRotation) {
                Text("0").tag(RotationAngle.angle0)
                Text("90").tag(RotationAngle.angle90)
                Text("180").tag(RotationAngle.angle180)
                Text("270").tag(RotationAngle.angle270)
            }
            .pickerStyle(.segmented)

            ProgressView(value: progress, total: 1)

            HStack {
                Button("Export with Harbeth") { exportVideo() }
                    .disabled(isProcessing)
                Button("Save") { saveVideo() }
                    .disabled(outputURL == nil)
            }
            .buttonStyle(.borderedProminent)

            Text(message).font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private func exportVideo() {
        guard let videoURL = Bundle.main.url(forResource: "IMG_1388", withExtension: "mp4") else {
            message = "Input video missing"
            return
        }
        isProcessing = true
        progress = 0
        let processor = HarbethFrameProcessor(filters: [C7LookupTable(name: "lut_abao"), C7Contrast(contrast: 0.9)])
        let filtering = FilterInstruction(processor: processor)
        let watermark = WatermarkInstruction(type: .text("Kakapos", font: .boldSystemFont(ofSize: 80), color: .red), position: .bottomRight, margin: 20, opacity: 0.8)
        var instructions: [CompositionInstruction] = [filtering, watermark]
        if selectedRotation != .angle0 {
            instructions.insert(RotateInstruction(rotationAngle: selectedRotation), at: 0)
        }
        let exporter = VideoX(provider: .init(with: videoURL))
        _ = exporter.export(options: [.OptimizeForNetworkUse: true], instructions: instructions, complete: { result in
            DispatchQueue.main.async {
                isProcessing = false
                switch result {
                case .success(let url):
                    outputURL = url
                    player = AVPlayer(url: url)
                    player?.play()
                    message = "Exported: \(url.lastPathComponent)"
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }, progress: { value in
            DispatchQueue.main.async { progress = value }
        })
    }

    private func saveVideo() {
        guard let outputURL = outputURL else { return }
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { message = "Photo Library permission denied" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    message = success ? "Saved to library" : (error?.localizedDescription ?? "Save failed")
                }
            })
        }
    }
}

private struct PlayerPreviewView: View {
    @State private var player: AVPlayer?
    @State private var previewImage: CGImage?
    @State private var frameCount = 0
    @State private var currentTimeText = "0.00s"
    @State private var message = "Tap Start to pull player frames into PreviewSink"
    #if canImport(UIKit)
    @State private var frameSource: PlayerFrameSource?
    @State private var pipeline: MediaPipeline?
    #endif

    var body: some View {
        VStack(spacing: 18) {
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

            HStack {
                Button("Start") { startPreview() }
                Button("Stop") { stopPreview() }
            }
            .buttonStyle(.borderedProminent)

            Text(message).font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
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
        #if canImport(UIKit)
        let source = PlayerFrameSource(player: player)
        let sink = PreviewSink { image, metadata in
            previewImage = image
            frameCount += 1
            currentTimeText = String(format: "%.2fs", metadata.presentationTime.seconds)
        }
        let pipeline = MediaPipeline(
            source: source,
            processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.1), C7Exposure(exposure: 0.15)])],
            sinks: [sink]
        )
        self.frameSource = source
        self.pipeline = pipeline
        pipeline.start()
        player.play()
        message = "Previewing processed player frames"
        #else
        message = "PlayerFrameSource is available in UIKit environments"
        #endif
    }

    private func stopPreview() {
        player?.pause()
        #if canImport(UIKit)
        pipeline?.stop()
        pipeline = nil
        frameSource = nil
        #endif
        previewImage = nil
        message = "Stopped"
    }
}

private struct CameraRecordView: View {
    @State private var player: AVPlayer?
    @State private var frameCount = 0
    @State private var recordedDurationText = "0.00s"
    @State private var sessionStateText = "idle"
    @State private var message = "Camera recording requires device camera permission"
    #if canImport(UIKit) && !os(watchOS)
    @State private var pipeline: MediaPipeline?
    @State private var cameraSource: CameraSource?
    @State private var recorder: RecorderSink?
    #endif

    var body: some View {
        VStack(spacing: 18) {
            VideoPlayer(player: player)
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.08))
                .cornerRadius(8)
            Text("Captured Frames: \(frameCount)").font(.headline)
            Text("Recorded Duration: \(recordedDurationText)").font(.subheadline).foregroundColor(.secondary)
            Text("Session State: \(sessionStateText)").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Button("Start Camera") { startCamera() }
                Button("Stop") { stopCamera() }
                Button("Flip Camera") { flipCamera() }
                    .disabled(cameraSource == nil)
            }
            .buttonStyle(.borderedProminent)
            Text(message).font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private func startCamera() {
        #if canImport(UIKit) && !os(watchOS)
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            DispatchQueue.main.async {
                guard allowed else {
                    message = "Camera permission denied"
                    return
                }
                do {
                    let source = try CameraSource()
                    let outputURL = try FileManager.default.kaka.createURL(prefix: "camera", pathExtension: "mp4")
                    let recorder = try RecorderSink(outputURL: outputURL)
                    source.sessionEventHandler = { event in
                        sessionStateText = String(describing: source.state)
                        switch event {
                        case .willStart:
                            message = "Starting camera session"
                        case .didStart:
                            message = "Recording camera frames"
                        case .didStop:
                            message = "Camera session stopped"
                        case .wasInterrupted:
                            recorder.pauseRecording()
                            message = "Camera session interrupted"
                        case .interruptionEnded:
                            recorder.resumeRecording()
                            message = "Camera interruption ended"
                        case .runtimeError(let isRecoverable, let description):
                            if isRecoverable {
                                message = "Camera runtime error, attempting recovery: \(description ?? "unknown")"
                            } else {
                                message = "Camera runtime error: \(description ?? "unknown")"
                            }
                        case .positionChanged(let position):
                            message = "Switched camera: \(String(describing: position))"
                        }
                    }
                    recorder.durationChangedHandler = { duration in
                        DispatchQueue.main.async {
                            recordedDurationText = String(format: "%.2fs", duration.seconds)
                        }
                    }
                    let counter = PixelBufferSink { _ in frameCount += 1 }
                    let pipeline = MediaPipeline(
                        source: source,
                        processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.05)])],
                        sinks: [counter, recorder]
                    )
                    pipeline.completionHandler = {
                        let clip = recorder.recordedClip ?? RecordedClip(outputURL: outputURL, duration: .zero, startedAt: nil, endedAt: nil)
                        player = AVPlayer(url: clip.outputURL)
                        player?.play()
                        recordedDurationText = String(format: "%.2fs", clip.duration.seconds)
                        message = "Recorded: \(clip.outputURL.lastPathComponent)"
                    }
                    self.cameraSource = source
                    self.recorder = recorder
                    self.pipeline = pipeline
                    frameCount = 0
                    recordedDurationText = "0.00s"
                    sessionStateText = String(describing: source.state)
                    pipeline.start()
                    message = "Starting camera session"
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        #else
        message = "CameraSource is available in UIKit camera environments"
        #endif
    }

    private func stopCamera() {
        #if canImport(UIKit) && !os(watchOS)
        pipeline?.stop()
        cameraSource = nil
        recorder = nil
        sessionStateText = "stopped"
        #else
        message = "CameraSource is unavailable here"
        #endif
    }

    private func flipCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let cameraSource else { return }
        let didSwitch = cameraSource.switchCameraPosition()
        if !didSwitch {
            message = "Failed to switch camera"
        }
        #endif
    }
}

private struct TimelineExportView: View {
    @State private var player: AVPlayer?
    @State private var message = "Compile a timeline from bundled clips"

    var body: some View {
        VStack(spacing: 18) {
            VideoPlayer(player: player)
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.08))
                .cornerRadius(8)
            Button("Compile Timeline") { compileTimeline() }
                .buttonStyle(.borderedProminent)
            Text(message).font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    private func compileTimeline() {
        guard let firstURL = Bundle.main.url(forResource: "IMG_1388", withExtension: "mp4"),
              let secondURL = Bundle.main.url(forResource: "IMG_3156", withExtension: "MOV") else {
            message = "Timeline assets missing"
            return
        }
        let timeline = TimelineComposition(renderSize: CGSize(width: 720, height: 1280), frameDuration: CMTime(value: 1, timescale: 30))
        timeline.addLayer(ClipLayer(asset: AVAsset(url: firstURL), timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600))))
        timeline.addLayer(ClipLayer(asset: AVAsset(url: secondURL), timeRange: CMTimeRange(start: CMTime(seconds: 3, preferredTimescale: 600), duration: CMTime(seconds: 3, preferredTimescale: 600))))
        let compiled = timeline.compile()
        let item = AVPlayerItem(asset: compiled.composition)
        item.videoComposition = compiled.videoComposition
        item.audioMix = compiled.audioMix
        player = AVPlayer(playerItem: item)
        player?.play()
        message = "Timeline compiled with \(compiled.composition.tracks.count) tracks"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
