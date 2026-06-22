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

    private var entry: KakaposSurface.Entry? {
        KakaposSurface.entry(board)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry?.displayName ?? board.displayName)
                    .font(.headline)
                Text(entry?.starterTypesText ?? board.starterTypes.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(entry?.summary ?? board.summary)
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
        do {
            let task = try KakaposSurface.exportTask(
                provider: .init(with: videoURL),
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
        #if canImport(UIKit) || os(macOS)
        let pipeline = KakaposSurface.preview(
            player: player,
            processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.1), C7Exposure(exposure: 0.15)])]
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

private struct CameraRecordView: View {
    private enum CameraPanel: String, CaseIterable {
        case preview = "Preview"
        case record = "Record"
        case photo = "Photo"
        case controls = "Controls"
        case advanced = "Advanced"
    }

    @State private var selectedPanel: CameraPanel = .preview
    @State private var player: AVPlayer?
    @State private var livePreviewImage: CGImage?
    @State private var photoImage: CGImage?
    @State private var frameCount = 0
    @State private var recordedDurationText = "0.00s"
    @State private var sessionStateText = "idle"
    @State private var recorderStateText = "idle"
    @State private var previewStateText = "idle"
    @State private var recorderSnapshotText = "segments: 0 · duration: 0.00s"
    @State private var deviceSnapshotText = "zoom 1.0 · torch off · flash off"
    @State private var advancedEventText = "Awaiting metadata, depth, or portrait events"
    @State private var lastOutputText = "none"
    @State private var message = "Camera engine requires device camera permission"
    #if canImport(UIKit) && !os(watchOS)
    @State private var engine: CameraEngine?
    @State private var previewController: CameraPreviewController?
    @State private var recordingController: CameraRecordingController?
    #endif

    var body: some View {
        VStack(spacing: 18) {
            BoardHeaderView(board: .record)
            Picker("Camera Panel", selection: $selectedPanel) {
                ForEach(CameraPanel.allCases, id: \.self) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            Group {
                if let livePreviewImage {
                    Image(decorative: livePreviewImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if let photoImage, selectedPanel == .photo {
                    Image(decorative: photoImage, scale: 1)
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
            Text(engine?.summaryText ?? "state idle · position unspecified · auth notDetermined · paused no · mode video")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(previewController?.previewSink?.summaryText ?? "state idle · frame n/a · presentation n/a · sourceTime n/a · reason n/a · image n/a · pending no")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(recordingController?.recorderSink.summaryText ?? "state idle · clips 0 · total 0.00s · clip 0.00s · recorded no")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack {
                Button("Start Preview") { startPreviewCamera() }
                Button("Start Record") { startRecordingCamera() }
                Button("Capture Photo") { capturePhoto() }
                Button("Stop") { stopCamera() }
                Button("Flip Camera") { flipCamera() }
                    .disabled(engine == nil)
            }
            .buttonStyle(.borderedProminent)
            HStack {
                Button("Pause") { pauseRecording() }
                    .disabled(recordingController == nil)
                Button("Resume") { resumeRecording() }
                    .disabled(recordingController == nil)
                Button("Zoom 1x") { updateZoom(1) }
                    .disabled(engine == nil)
                Button("Zoom 2x") { updateZoom(2) }
                    .disabled(engine == nil)
            }
            .buttonStyle(.bordered)
            HStack {
                Button("Torch On") { setTorch(true) }
                    .disabled(engine == nil)
                Button("Torch Off") { setTorch(false) }
                    .disabled(engine == nil)
                Button("EV -1") { setExposureBias(-1) }
                    .disabled(engine == nil)
                Button("EV 0") { setExposureBias(0) }
                    .disabled(engine == nil)
                Button("EV +1") { setExposureBias(1) }
                    .disabled(engine == nil)
            }
            .buttonStyle(.bordered)
            panelBody
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

    @ViewBuilder
    private var panelBody: some View {
        switch selectedPanel {
        case .preview:
            Text("Processed preview runs through HarbethFrameProcessor and PreviewSink.")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .record:
            Text("Recording uses CameraRecordingController over RecorderSink and RecordingSession.")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .photo:
            Text(photoImage == nil ? "No photo captured yet" : "Showing latest captured photo")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .controls:
            Text(deviceSnapshotText)
                .font(.footnote)
                .foregroundColor(.secondary)
        case .advanced:
            Text(advancedEventText)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func startPreviewCamera() {
        startCamera(recordingEnabled: false)
    }

    private func startRecordingCamera() {
        startCamera(recordingEnabled: true)
    }

    private func startCamera(recordingEnabled: Bool) {
        #if canImport(UIKit) && !os(watchOS)
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            DispatchQueue.main.async {
                guard allowed else {
                    message = "Camera permission denied"
                    return
                }
                do {
                    stopCamera()
                    let configuration = CameraCaptureConfiguration(
                        captureMode: .video,
                        preferredPosition: .back,
                        preferredDeviceTypes: [.wideAngle, .trueDepth],
                        video: .init(
                            sessionPreset: .high,
                            preferredFrameRateRange: .init(minimumFramesPerSecond: 24, maximumFramesPerSecond: 60),
                            preferredStabilizationMode: .auto
                        ),
                        photo: .init(
                            deliversDepthData: true,
                            deliversPortraitEffectsMatte: true
                        ),
                        advanced: .init(
                            metadataObjectTypes: [.face, .qr],
                            enablesDepthData: true,
                            enablesPortraitEffectsMatte: true
                        )
                    )
                    let engine = try KakaposSurface.camera(configuration: configuration)
                    let previewController = engine.makePreviewController(
                        mode: .processed,
                        processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.05), C7Exposure(exposure: 0.05)])],
                        callbackQueue: .main
                    ) { image, metadata in
                        frameCount += 1
                        livePreviewImage = image
                        lastOutputText = "video @ \(String(format: "%.2fs", metadata.presentationTime.seconds))"
                        previewStateText = "active"
                    }
                    engine.source.sessionEventHandler = { event in
                        sessionStateText = String(describing: engine.source.state)
                        switch event {
                        case .willStart:
                            message = "Starting camera session"
                        case .didStart:
                            message = recordingEnabled ? "Recording camera frames" : "Previewing camera frames"
                        case .didPause:
                            message = "Camera session paused"
                        case .didResume:
                            message = "Camera session resumed"
                        case .didStop:
                            message = "Camera session stopped"
                        case .wasInterrupted:
                            engine.source.pause()
                            recordingController?.pause()
                            message = "Camera session interrupted"
                        case .interruptionEnded:
                            engine.source.resume()
                            recordingController?.resume()
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
                    engine.source.photoCaptureHandler = { result in
                        DispatchQueue.main.async {
                            if let data = result.data, let image = UIImage(data: data)?.cgImage {
                                photoImage = image
                            }
                            lastOutputText = result.isFromCurrentFrame ? "photo fallback frame" : "photo output"
                            advancedEventText = "photo · depth \(result.depthDataDelivered ? "yes" : "no") · portrait \(result.portraitEffectsMatteDelivered ? "yes" : "no")"
                            message = "Captured photo"
                        }
                    }
                    engine.advancedOutput.metadataObjectsHandler = { payload in
                        DispatchQueue.main.async {
                            let ts = payload.timestamp?.seconds ?? 0
                            advancedEventText = "metadata \(payload.objects.count) @ \(String(format: "%.2fs", ts))"
                        }
                    }
                    engine.advancedOutput.depthDataHandler = { payload in
                        DispatchQueue.main.async {
                            advancedEventText = "depth @ \(String(format: "%.2fs", payload.timestamp.seconds))"
                        }
                    }
                    engine.advancedOutput.portraitEffectsMatteHandler = { payload in
                        DispatchQueue.main.async {
                            advancedEventText = "portrait matte \(payload.deliveredInPhoto ? "photo" : "stream")"
                        }
                    }
                    self.engine = engine
                    self.previewController = previewController
                    self.recordingController = nil
                    self.player = nil
                    self.photoImage = nil
                    self.livePreviewImage = nil
                    frameCount = 0
                    recordedDurationText = "0.00s"
                    sessionStateText = String(describing: engine.source.state)
                    recorderStateText = "idle"
                    previewStateText = String(describing: previewController.previewSink?.state ?? .idle)
                    recorderSnapshotText = "segments: 0 · duration: 0.00s"
                    deviceSnapshotText = snapshotText(for: engine.deviceController.snapshot)
                    advancedEventText = "Awaiting metadata, depth, or portrait events"
                    lastOutputText = "awaiting frames"
                    engine.start()
                    message = recordingEnabled ? "Starting camera recording" : "Starting camera preview"
                    if recordingEnabled {
                        let outputURL = try FileManager.default.kaka.createURL(prefix: "camera", pathExtension: "mp4")
                        let recordingController = try engine.makeRecordingController(
                            outputURL: outputURL,
                            processors: [HarbethFrameProcessor(filters: [C7Contrast(contrast: 1.05), C7Exposure(exposure: 0.05)])]
                        )
                        recordingController.eventHandler = { event in
                            DispatchQueue.main.async {
                                switch event {
                                case .didStart:
                                    recorderStateText = "recording"
                                case .didPause:
                                    recorderStateText = "paused"
                                case .didResume:
                                    recorderStateText = "recording"
                                case .didFinish:
                                    recorderStateText = "finished"
                                case .didCancel:
                                    recorderStateText = "cancelled"
                                case .clipCountChanged:
                                    break
                                case .durationChanged(let duration):
                                    recordedDurationText = String(format: "%.2fs", duration.seconds)
                                }
                                recorderSnapshotText = snapshotText(for: recordingController.recorderSink.snapshot)
                            }
                        }
                        self.recordingController = recordingController
                        recordingController.start()
                    }
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
        if let recordingController {
            let recorder = recordingController.recorderSink
            recordingController.finishRecording { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let clip):
                        if let clipURL = clip.outputURL {
                            player = AVPlayer(url: clipURL)
                            player?.play()
                            lastOutputText = clipURL.lastPathComponent
                            message = "Recorded: \(clipURL.lastPathComponent)"
                        } else {
                            message = "Recording finished"
                        }
                        recordedDurationText = String(format: "%.2fs", clip.duration.seconds)
                        recorderSnapshotText = snapshotText(for: recorder.snapshot)
                    case .failure(let error):
                        message = error.localizedDescription
                    }
                }
            }
        }
        engine?.stop()
        livePreviewImage = nil
        previewController = nil
        recordingController = nil
        engine = nil
        sessionStateText = "stopped"
        recorderStateText = "finished"
        previewStateText = "finished"
        recorderSnapshotText = "segments: 0 · duration: 0.00s"
        #else
        message = "CameraSource is unavailable here"
        #endif
    }

    private func pauseRecording() {
        #if canImport(UIKit) && !os(watchOS)
        recordingController?.pause()
        engine?.pause()
        recorderStateText = "paused"
        previewStateText = "paused"
        if let recorder = recordingController?.recorderSink {
            recorderSnapshotText = snapshotText(for: recorder.snapshot)
        }
        message = "Recording paused"
        #endif
    }

    private func resumeRecording() {
        #if canImport(UIKit) && !os(watchOS)
        engine?.resume()
        recordingController?.resume()
        recorderStateText = "recording"
        previewStateText = "active"
        if let recorder = recordingController?.recorderSink {
            recorderSnapshotText = snapshotText(for: recorder.snapshot)
        }
        message = "Recording resumed"
        #endif
    }

    private func flipCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else { return }
        let didSwitch = engine.switchCameraPosition()
        if !didSwitch {
            message = "Failed to switch camera"
        } else {
            deviceSnapshotText = snapshotText(for: engine.deviceController.snapshot)
            lastOutputText = "camera: \(String(describing: engine.source.currentPosition))"
        }
        #endif
    }

    private func capturePhoto() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else {
            message = "Start preview before capturing a photo"
            return
        }
        engine.capturePhoto()
        #endif
    }

    private func updateZoom(_ zoomFactor: CGFloat) {
        #if canImport(UIKit) && !os(watchOS)
        do {
            if let snapshot = try engine?.setZoomFactor(zoomFactor) {
                deviceSnapshotText = snapshotText(for: snapshot)
            }
        } catch {
            message = error.localizedDescription
        }
        #endif
    }

    private func setExposureBias(_ bias: Float) {
        #if canImport(UIKit) && !os(watchOS)
        do {
            if let snapshot = try engine?.setExposureBias(bias) {
                deviceSnapshotText = snapshotText(for: snapshot)
            }
        } catch {
            message = error.localizedDescription
        }
        #endif
    }

    private func setTorch(_ enabled: Bool) {
        #if canImport(UIKit) && !os(watchOS)
        do {
            if let snapshot = try engine?.setTorchActive(enabled) {
                deviceSnapshotText = snapshotText(for: snapshot)
            }
        } catch {
            message = error.localizedDescription
        }
        #endif
    }

    private func snapshotText(for snapshot: RecorderSink.Snapshot) -> String {
        let duration = String(format: "%.2fs", snapshot.totalDuration.seconds)
        return "segments: \(snapshot.clipCount) · video: \(snapshot.recordedVideoSegmentCount) · audio: \(snapshot.recordedAudioSegmentCount) · duration: \(duration)"
    }

    private func snapshotText(for snapshot: CameraDeviceSnapshot) -> String {
        let zoom = String(format: "%.1f", snapshot.zoomFactor)
        let bias = String(format: "%.1f", snapshot.exposureBias ?? 0)
        return "zoom \(zoom)x · ev \(bias) · torch \(snapshot.torchActive ? "on" : "off") · flash \(snapshot.flashAvailable ? "ready" : "off")"
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
