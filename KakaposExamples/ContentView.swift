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

private struct BoardHeaderView: View {
    let board: KakaposCapabilityBoard

    private var info: KakaposCapabilityBoardInfo? {
        KakaposCapabilityCatalog.board(named: board.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(info?.displayName ?? board.displayName)
                    .font(.headline)
                Text((info?.starterTypes ?? board.starterTypes).joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(info?.summary ?? board.summary)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct OfflineExportView: View {
    @State private var player: AVPlayer?
    @State private var outputURL: URL?
    @State private var exportTask: VideoX.ExportTask?
    @State private var isProcessing = false
    @State private var progress: Float = 0
    @State private var progressDetail = "Progress detail unavailable"
    @State private var message = "Ready"
    @State private var taskStatus = "idle"
    @State private var selectedRotation: RotationAngle = .angle0

    var body: some View {
        VStack(spacing: 18) {
            BoardHeaderView(board: .export)
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
            Text(progressDetail)
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack {
                Button("Export") { exportVideo() }
                    .disabled(isProcessing)
                Button("Cancel") { cancelExport() }
                    .disabled(exportTask == nil || !isProcessing)
                Button("Save") { saveVideo() }
                    .disabled(outputURL == nil)
            }
            .buttonStyle(.borderedProminent)

            if exportTask?.supportsPauseResume == true {
                HStack {
                    Button("Pause") { pauseExport() }
                        .disabled(taskStatus != "exporting")
                    Button("Resume") { resumeExport() }
                        .disabled(taskStatus != "paused")
                }
                .buttonStyle(.bordered)
            }

            Text("Task Status: \(taskStatus)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(exportTask?.summaryText ?? "state idle · pipeline unavailable")
                .font(.footnote)
                .foregroundColor(.secondary)
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
        progressDetail = "Starting export..."
        let processor = HarbethFrameProcessor(filters: [C7LookupTable(name: "lut_abao"), C7Contrast(contrast: 0.9)])
        let filtering = FilterInstruction(processor: processor)
        let watermark = WatermarkInstruction(type: .text("Kakapos", font: .boldSystemFont(ofSize: 80), color: .red), position: .bottomRight, margin: 20, opacity: 0.8)
        var instructions: [CompositionInstruction] = [filtering, watermark]
        if selectedRotation != .angle0 {
            instructions.insert(RotateInstruction(rotationAngle: selectedRotation), at: 0)
        }
        let exporter = VideoX(provider: .init(with: videoURL))
        do {
            let task = try exporter.makeExportTask(
                options: [
                    .OptimizeForNetworkUse: true,
                    .ExportPipeline: VideoX.ExportPipeline.readerWriter
                ],
                instructions: instructions
            )
            exportTask = task
            taskStatus = statusText(for: task.status)
            task.readerWriterJob?.statusHandler = { status in
                DispatchQueue.main.async {
                    taskStatus = statusText(for: status)
                }
            }
            task.start(complete: { result in
                DispatchQueue.main.async {
                    isProcessing = false
                    exportTask = nil
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
            }, progressInfo: { info in
                DispatchQueue.main.async {
                    progressDetail = progressDetailText(for: info)
                }
            })
        } catch {
            isProcessing = false
            exportTask = nil
            taskStatus = "failed"
            message = error.localizedDescription
        }
    }

    private func pauseExport() {
        exportTask?.pause()
        taskStatus = statusText(for: exportTask?.status ?? .idle)
    }

    private func resumeExport() {
        exportTask?.resume()
        taskStatus = statusText(for: exportTask?.status ?? .idle)
    }

    private func cancelExport() {
        exportTask?.cancel()
        taskStatus = statusText(for: exportTask?.status ?? .idle)
    }

    private func statusText(for status: VideoX.ExportTask.Status) -> String {
        switch status {
        case .idle:
            return "idle"
        case .exporting:
            return "exporting"
        case .paused:
            return "paused"
        case .completed:
            return "completed"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        }
    }

    private func statusText(for status: ReaderWriterExportJob.Status) -> String {
        switch status {
        case .idle:
            return "idle"
        case .exporting:
            return "exporting"
        case .paused:
            return "paused"
        case .completed:
            return "completed"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        }
    }

    private func progressDetailText(for info: ReaderWriterExportJob.ProgressInfo) -> String {
        let videoText = info.hasVideo ? Self.percentageText(info.videoProgress) : "n/a"
        let audioText = info.hasAudio ? Self.percentageText(info.audioProgress) : "n/a"
        let finishText = Self.percentageText(info.finishWritingProgress)
        return "Video \(videoText) · Audio \(audioText) · Finish \(finishText)"
    }

    private static func percentageText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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
    @State private var previewStateText = "idle"
    @State private var previewGeneration: Int64 = 0
    #if canImport(UIKit)
    @State private var frameSource: PlayerFrameSource?
    @State private var previewSink: PreviewSink?
    @State private var pipeline: MediaPipeline?
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
            #if canImport(UIKit)
            Text(frameSource?.summaryText ?? "state idle · generation 0 · frame 0 · lastFrame no · seekTarget no · fps 30")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(previewSink?.summaryText ?? "state idle · frame n/a · image n/a · pending no")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(pipeline?.summary.summaryText ?? "source unavailable · processors 0 · sinks 0 · state idle")
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
        #if canImport(UIKit)
        let sink = PreviewSink { image, metadata in
            let generation = metadata.userInfo[PlayerFrameSource.MetadataKey.generation] as? Int64 ?? 0
            guard generation >= previewGeneration else { return }
            previewGeneration = generation
            previewImage = image
            frameCount += 1
            currentTimeText = String(format: "%.2fs", metadata.presentationTime.seconds)
            previewStateText = metadata.userInfo[PlayerFrameSource.MetadataKey.playbackState] as? String ?? "running"
        }
        let pipeline = MediaPipeline(
            player: player,
            processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.1), C7Exposure(exposure: 0.15)])],
            sinks: [sink]
        )
        self.frameSource = pipeline.source as? PlayerFrameSource
        self.previewSink = sink
        self.pipeline = pipeline
        pipeline.start()
        player.play()
        message = "Previewing processed player frames"
        previewStateText = "running"
        #else
        message = "PlayerFrameSource is available in UIKit environments"
        #endif
    }

    private func pausePreview() {
        player?.pause()
        #if canImport(UIKit)
        pipeline?.pause()
        #endif
        previewStateText = "paused"
        message = "Preview paused"
    }

    private func resumePreview() {
        #if canImport(UIKit)
        pipeline?.resume()
        #endif
        player?.play()
        previewStateText = "running"
        message = "Preview resumed"
    }

    private func restartPreview() {
        seekPreview(to: .zero, message: "Preview restarted from zero")
    }

    private func seekPreview(to time: CMTime, message: String = "Preview seeked") {
        #if canImport(UIKit)
        frameSource?.seek(to: time) { finished in
            guard finished else { return }
            DispatchQueue.main.async {
                self.player?.play()
                self.previewStateText = "running"
                self.currentTimeText = String(format: "%.2fs", time.seconds)
                self.message = message
            }
        }
        if frameSource == nil {
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
        #if canImport(UIKit)
        pipeline?.stop()
        pipeline = nil
        frameSource = nil
        previewSink = nil
        #endif
        previewImage = nil
        previewStateText = "stopped"
        previewGeneration = 0
        message = "Stopped"
    }
}

private struct CameraRecordView: View {
    @State private var player: AVPlayer?
    @State private var livePreviewImage: CGImage?
    @State private var frameCount = 0
    @State private var recordedDurationText = "0.00s"
    @State private var sessionStateText = "idle"
    @State private var recorderStateText = "idle"
    @State private var previewStateText = "idle"
    @State private var recorderSnapshotText = "segments: 0 · duration: 0.00s"
    @State private var lastOutputText = "none"
    @State private var message = "Camera recording requires device camera permission"
    #if canImport(UIKit) && !os(watchOS)
    @State private var pipeline: MediaPipeline?
    @State private var cameraSource: CameraSource?
    @State private var recorder: RecorderSink?
    @State private var previewSink: PreviewSink?
    #endif

    var body: some View {
        VStack(spacing: 18) {
            BoardHeaderView(board: .record)
            Group {
                if let livePreviewImage {
                    Image(decorative: livePreviewImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    VideoPlayer(player: player)
                }
            }
            .frame(maxHeight: 280)
            .background(Color.black.opacity(0.08))
            .cornerRadius(8)
            Text("Captured Frames: \(frameCount)").font(.headline)
            Text("Recorded Duration: \(recordedDurationText)").font(.subheadline).foregroundColor(.secondary)
            Text("Session State: \(sessionStateText)").font(.subheadline).foregroundColor(.secondary)
            Text("Recorder State: \(recorderStateText)").font(.subheadline).foregroundColor(.secondary)
            Text("Preview State: \(previewStateText)").font(.subheadline).foregroundColor(.secondary)
            Text("Recorder Snapshot: \(recorderSnapshotText)").font(.footnote).foregroundColor(.secondary)
            #if canImport(UIKit) && !os(watchOS)
            Text(cameraSource?.summaryText ?? "state idle · position unspecified · auth notDetermined · paused no · mode video")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(previewSink?.summaryText ?? "state idle · frame n/a · presentation n/a · sourceTime n/a · reason n/a · image n/a · pending no")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(recorder?.summaryText ?? "state idle · clips 0 · total 0.00s · clip 0.00s · recorded no")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack {
                Button("Start Camera") { startCamera() }
                Button("Pause Record") { pauseRecording() }
                    .disabled(recorder == nil)
                Button("Resume Record") { resumeRecording() }
                    .disabled(recorder == nil)
                Button("Stop") { stopCamera() }
                Button("Flip Camera") { flipCamera() }
                    .disabled(cameraSource == nil)
            }
            .buttonStyle(.borderedProminent)
            #endif
            Text("Last Output: \(lastOutputText)").font(.subheadline).foregroundColor(.secondary)
            #if !(canImport(UIKit) && !os(watchOS))
            Text("Camera controls unavailable on this platform")
                .font(.footnote)
                .foregroundColor(.secondary)
            #endif
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
                        case .didPause:
                            message = "Camera session paused"
                        case .didResume:
                            message = "Camera session resumed"
                        case .didStop:
                            message = "Camera session stopped"
                        case .wasInterrupted:
                            source.pause()
                            recorder.pauseRecording()
                            message = "Camera session interrupted"
                        case .interruptionEnded:
                            source.resume()
                            recorder.resumeRecording()
                            message = "Camera interruption ended"
                        case .runtimeError(let isRecoverable, let description):
                            if isRecoverable {
                                message = "Camera runtime error, attempting recovery: \(description ?? "unknown")"
                            } else {
                                message = "Camera runtime error: \(description ?? "unknown")"
                            }
                        case .willSwitchPosition(let position):
                            message = "Switching camera: \(String(describing: position))"
                        case .positionChanged(let position):
                            message = "Switched camera: \(String(describing: position))"
                        case .authorizationChanged(let status):
                            message = "Camera authorization: \(status.description)"
                        }
                    }
                    recorder.durationChangedHandler = { duration in
                        DispatchQueue.main.async {
                            recordedDurationText = String(format: "%.2fs", duration.seconds)
                            recorderSnapshotText = snapshotText(for: recorder.snapshot)
                        }
                    }
                    recorder.stateChangedHandler = { state in
                        recorderStateText = String(describing: state)
                        recorderSnapshotText = snapshotText(for: recorder.snapshot)
                    }
                    let preview = PreviewSink(callbackQueue: .main) { image, metadata in
                        frameCount += 1
                        livePreviewImage = image
                        lastOutputText = "video @ \(String(format: "%.2fs", metadata.presentationTime.seconds))"
                        previewStateText = "active"
                    }
                    preview.stateChangedHandler = { state in
                        previewStateText = String(describing: state)
                    }
                    let pipeline = MediaPipeline(
                        source: source,
                        processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.05)])],
                        sinks: [preview, recorder]
                    )
                    pipeline.errorHandler = { error in
                        message = "Pipeline error: \(error.localizedDescription)"
                    }
                    pipeline.completionHandler = {
                        let clip = recorder.recordedClip ?? RecordedClip(outputURL: outputURL, duration: .zero, startedAt: nil, endedAt: nil)
                        guard let clipURL = clip.outputURL else {
                            message = "Recording finished without output URL"
                            return
                        }
                        player = AVPlayer(url: clipURL)
                        player?.play()
                        livePreviewImage = nil
                        recordedDurationText = String(format: "%.2fs", clip.duration.seconds)
                        recorderStateText = String(describing: recorder.state)
                        recorderSnapshotText = snapshotText(for: recorder.snapshot)
                        lastOutputText = clipURL.lastPathComponent
                        message = "Recorded: \(clipURL.lastPathComponent)"
                    }
                    self.cameraSource = source
                    self.recorder = recorder
                    self.previewSink = preview
                    self.pipeline = pipeline
                    self.player = nil
                    self.livePreviewImage = nil
                    frameCount = 0
                    recordedDurationText = "0.00s"
                    sessionStateText = String(describing: source.state)
                    recorderStateText = String(describing: recorder.state)
                    previewStateText = String(describing: preview.state)
                    recorderSnapshotText = snapshotText(for: recorder.snapshot)
                    lastOutputText = "awaiting frames"
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
        previewSink = nil
        livePreviewImage = nil
        sessionStateText = "stopped"
        recorderStateText = "finished"
        previewStateText = "finished"
        recorderSnapshotText = "segments: 0 · duration: 0.00s"
        cameraSource = nil
        recorder = nil
        previewSink = nil
        pipeline = nil
        #else
        message = "CameraSource is unavailable here"
        #endif
    }

    private func pauseRecording() {
        #if canImport(UIKit) && !os(watchOS)
        cameraSource?.pause()
        recorder?.pauseRecording()
        recorderStateText = "paused"
        previewStateText = "paused"
        if let recorder {
            recorderSnapshotText = snapshotText(for: recorder.snapshot)
        }
        message = "Recording paused"
        #endif
    }

    private func resumeRecording() {
        #if canImport(UIKit) && !os(watchOS)
        cameraSource?.resume()
        recorder?.resumeRecording()
        recorderStateText = "recording"
        previewStateText = "active"
        if let recorder {
            recorderSnapshotText = snapshotText(for: recorder.snapshot)
        }
        message = "Recording resumed"
        #endif
    }

    private func flipCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let cameraSource else { return }
        let didSwitch = cameraSource.switchCameraPosition()
        if !didSwitch {
            message = "Failed to switch camera"
        } else {
            lastOutputText = "camera: \(String(describing: cameraSource.currentPosition))"
        }
        #endif
    }

    private func snapshotText(for snapshot: RecorderSink.Snapshot) -> String {
        let duration = String(format: "%.2fs", snapshot.totalDuration.seconds)
        return "segments: \(snapshot.clipCount) · video: \(snapshot.recordedVideoSegmentCount) · audio: \(snapshot.recordedAudioSegmentCount) · duration: \(duration)"
    }
}

private struct TimelineExportView: View {
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
                keyTimes: [
                    secondClip.timeRange.start,
                    secondClip.timeRange.end
                ]
            ),
            KeyframeAnimation(
                keyPath: "translation.y",
                values: [180, 0],
                keyTimes: [
                    secondClip.timeRange.start,
                    secondClip.timeRange.end
                ],
                easing: .easeOut
            ),
            KeyframeAnimation(
                keyPath: "scale",
                values: [0.82, 1.0],
                keyTimes: [
                    secondClip.timeRange.start,
                    secondClip.timeRange.end
                ],
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
