//
//  CameraRecordView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI
import AVFoundation
import AVKit
import Harbeth

struct CameraRecordView: View {
    @ObservedObject var mediaStore: ExampleAppState

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
    @State private var clipPreviewStateText = "idle"
    @State private var clipExportStateText = "idle"
    @State private var clipPreviewImage: CGImage?
    @State private var clipPreviewPipeline: PreviewPipeline?
    @State private var clipExportTask: TimelineExportTask?
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
            Text("Clip Preview: \(clipPreviewStateText)").font(.subheadline).foregroundColor(.secondary)
            Text("Clip Export: \(clipExportStateText)").font(.subheadline).foregroundColor(.secondary)
            Text("Recorder Snapshot: \(recorderSnapshotText)").font(.footnote).foregroundColor(.secondary)
            Text(mediaStore.latestRecordedClipSummaryText).font(.footnote).foregroundColor(.secondary)
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
            HStack {
                Button("Clip Preview") { previewRecordedClip() }
                    .disabled(mediaStore.latestRecordedClip == nil)
                Button("Clip Timeline") { playRecordedClipTimeline() }
                    .disabled(mediaStore.latestRecordedClip == nil)
                Button("Clip Export") { exportRecordedClip() }
                    .disabled(mediaStore.latestRecordedClip == nil || clipExportTask != nil)
                Button("Stop Clip Flow") { stopRecordedClipFlow() }
                    .disabled(mediaStore.latestRecordedClip == nil && clipPreviewPipeline == nil && clipExportTask == nil)
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
        #if !os(macOS)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    @ViewBuilder
    private var panelBody: some View {
        switch selectedPanel {
        case .preview:
            Text(clipPreviewImage == nil ? "Processed preview runs through the example-owned Harbeth adapter and PreviewSink." : "Showing latest processed recorded-clip frame")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .record:
            Text(mediaStore.latestRecordedClip == nil ? "Recording uses CameraRecordingController over RecorderSink and RecordingSession." : "Recorded clips can bridge directly into Preview, Timeline, and Export.")
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
                    let previewController = engine.startPreview(
                        mode: .processed,
                        processors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.05), C7Exposure(exposure: 0.05)])],
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
                        case .wasInterrupted, .wasInterruptedWhileRecording:
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
                        case .systemPressureChanged(let summary):
                            message = "Camera pressure changed: \(summary)"
                        case .audioRouteChanged(let route):
                            message = "Audio route changed: \(route)"
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
                            advancedEventText = CameraAdvancedEvent.metadataObjects(.init(objects: payload.objects, timestamp: payload.timestamp)).summaryText
                            if payload.objects.isEmpty {
                                advancedEventText = "metadataObjects count 0 · timestamp \(String(format: "%.2fs", ts))"
                            }
                        }
                    }
                    engine.advancedOutput.depthDataHandler = { payload in
                        DispatchQueue.main.async {
                            advancedEventText = CameraAdvancedEvent.depthData(payload).summaryText
                        }
                    }
                    engine.advancedOutput.portraitEffectsMatteHandler = { payload in
                        DispatchQueue.main.async {
                            advancedEventText = CameraAdvancedEvent.portraitEffectsMatte(payload).summaryText
                        }
                    }
                    self.engine = engine
                    self.previewController = previewController
                    self.recordingController = nil
                    self.mediaStore.clearRecordedClip()
                    self.player = nil
                    self.photoImage = nil
                    self.livePreviewImage = nil
                    self.clipPreviewImage = nil
                    self.clipPreviewPipeline?.stop()
                    self.clipPreviewPipeline = nil
                    self.clipExportTask = nil
                    frameCount = 0
                    recordedDurationText = "0.00s"
                    sessionStateText = String(describing: engine.source.state)
                    recorderStateText = "idle"
                    previewStateText = String(describing: previewController.previewSink?.state ?? .idle)
                    clipPreviewStateText = "idle"
                    clipExportStateText = "idle"
                    recorderSnapshotText = "segments: 0 · duration: 0.00s"
                    deviceSnapshotText = engine.deviceSummaryText
                    advancedEventText = "Awaiting metadata, depth, or portrait events"
                    lastOutputText = "awaiting frames"
                    message = recordingEnabled ? "Starting camera recording" : "Starting camera preview"
                    if recordingEnabled {
                        let outputURL = try FileManager.default.kaka.createURL(prefix: "camera", pathExtension: "mp4")
                        let recordingController = try engine.startRecording(
                            outputURL: outputURL,
                            processors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.05), C7Exposure(exposure: 0.05)])]
                        )
                        recordingController.eventHandler = { event in
                            DispatchQueue.main.async {
                                switch event {
                                case .willStart:
                                    recorderStateText = "preparing"
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
                                case .didFail(let description):
                                    recorderStateText = "failed"
                                    message = "Recording failed: \(description)"
                                case .clipCompleted:
                                    break
                                case .clipCountChanged:
                                    break
                                case .durationChanged(let duration):
                                    recordedDurationText = String(format: "%.2fs", duration.seconds)
                                case .droppedFrame:
                                    break
                                }
                                recorderSnapshotText = snapshotText(for: recordingController.recorderSink.snapshot)
                            }
                        }
                        self.recordingController = recordingController
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
        if let engine {
            let recorder = engine.recordingController?.recorderSink
            engine.stopRecording { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let clip):
                        mediaStore.updateRecordedClip(clip)
                        if let clipURL = clip.outputURL {
                            player = AVPlayer(url: clipURL)
                            player?.play()
                            lastOutputText = clipURL.lastPathComponent
                            message = "Recorded: \(clipURL.lastPathComponent)"
                        } else {
                            message = "Recording finished"
                        }
                        recordedDurationText = String(format: "%.2fs", clip.duration.seconds)
                        clipPreviewStateText = "ready"
                        clipExportStateText = "ready"
                        if let recorder {
                            recorderSnapshotText = snapshotText(for: recorder.snapshot)
                        }
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

    private func previewRecordedClip() {
        #if canImport(UIKit) || os(macOS)
        guard let recordedClip = mediaStore.latestRecordedClip else {
            message = "No recorded clip available"
            return
        }
        clipPreviewPipeline?.stop()
        clipPreviewImage = nil
        livePreviewImage = nil
        player?.pause()
        player = nil
        let pipeline = KakaposSurface.preview(
            recordedClip: recordedClip,
            processors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.08), C7Exposure(exposure: 0.08)])],
            callbackQueue: .main
        ) { image, metadata in
            clipPreviewImage = image
            livePreviewImage = image
            lastOutputText = "clip preview @ \(String(format: "%.2fs", metadata.presentationTime.seconds))"
            clipPreviewStateText = "running"
        }
        guard let pipeline else {
            message = "Recorded clip preview unavailable"
            clipPreviewStateText = "failed"
            return
        }
        clipPreviewPipeline = pipeline
        pipeline.start()
        clipPreviewStateText = "running"
        previewStateText = "clip-preview"
        message = "Previewing recorded clip through KakaposSurface.preview(recordedClip:)"
        #endif
    }

    private func playRecordedClipTimeline() {
        guard let recordedClip = mediaStore.latestRecordedClip else {
            message = "No recorded clip available"
            return
        }
        stopRecordedClipFlow()
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
        lastOutputText = "clip timeline"
        clipPreviewStateText = "timeline"
        message = "Playing recorded clip through TimelinePipeline"
    }

    private func exportRecordedClip() {
        guard let recordedClip = mediaStore.latestRecordedClip else {
            message = "No recorded clip available"
            return
        }
        do {
            let outputURL = try FileManager.default.kaka.createURL(prefix: "clip-export", pathExtension: "mp4")
            guard let task = KakaposSurface.timelineExportTask(
                recordedClip: recordedClip,
                outputURL: outputURL,
                videoProcessors: [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.1), C7Exposure(exposure: 0.12)])]
            ) else {
                clipExportStateText = "failed"
                message = "Recorded clip export unavailable"
                return
            }
            clipExportTask = task
            clipExportStateText = "exporting"
            message = "Exporting recorded clip through TimelineExportTask"
            task.start(complete: { result in
                DispatchQueue.main.async {
                    clipExportTask = nil
                    switch result {
                    case .success(let url):
                        clipExportStateText = "completed"
                        player = AVPlayer(url: url)
                        player?.play()
                        lastOutputText = url.lastPathComponent
                        message = "Clip exported: \(url.lastPathComponent)"
                    case .failure(let error):
                        clipExportStateText = "failed"
                        message = error.localizedDescription
                    }
                }
            })
        } catch {
            clipExportStateText = "failed"
            message = error.localizedDescription
        }
    }

    private func stopRecordedClipFlow() {
        clipPreviewPipeline?.stop()
        clipPreviewPipeline = nil
        clipExportTask?.cancel()
        clipExportTask = nil
        clipPreviewImage = nil
        livePreviewImage = nil
        clipPreviewStateText = mediaStore.latestRecordedClip == nil ? "idle" : "ready"
        clipExportStateText = mediaStore.latestRecordedClip == nil ? "idle" : "ready"
    }

    private func flipCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else { return }
        let didSwitch = engine.switchCameraPosition()
        if !didSwitch {
            message = "Failed to switch camera"
        } else {
            deviceSnapshotText = engine.deviceSummaryText
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
                deviceSnapshotText = snapshot.summaryText
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
                deviceSnapshotText = snapshot.summaryText
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
                deviceSnapshotText = snapshot.summaryText
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
}
