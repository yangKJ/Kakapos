//
//  CameraShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI
import AVFoundation
import AVKit
import Harbeth
import Kakapos

struct CameraShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    private enum CaptureMode: String, CaseIterable {
        case video = "Video"
        case photo = "Photo"
        case processed = "Processed"
    }

    @State private var captureMode: CaptureMode = .video
    @State private var previewImage: CGImage?
    @State private var photoImage: CGImage?
    @State private var player: AVPlayer?
    @State private var frameCount = 0
    @State private var recordedDurationText = "00:00"
    @State private var lensText = "1x"
    @State private var qualityText = "1080p"
    @State private var statusText = "Ready"
    @State private var outputText = "No clip"
    @State private var isRecording = false
    @State private var isPreviewing = false
    @State private var isTorchOn = false
    @State private var showLab = false
    @State private var recentEventText = "Camera Engine"
    @State private var clipExportTask: TimelineExportTask?
    #if canImport(UIKit) && !os(watchOS)
    @State private var engine: CameraEngine?
    @State private var previewController: CameraPreviewController?
    @State private var recordingController: CameraRecordingController?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewSurface
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                bottomDock
            }
        }
        .sheet(isPresented: $showLab) {
            CameraRecordView(mediaStore: mediaStore)
        }
        .onAppear {
            statusText = "Tap preview or record"
        }
        #if !os(macOS)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    @ViewBuilder
    private var previewSurface: some View {
        if let previewImage {
            Image(decorative: previewImage, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if let photoImage {
            Image(decorative: photoImage, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if let player {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CameraShowcasePlaceholder(statusText: statusText)
        }
    }

    private var topChrome: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kakapos Camera Engine")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(recentEventText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer()
                CameraHUDPill(icon: "timer", text: recordedDurationText, active: isRecording)
                CameraHUDPill(icon: "viewfinder", text: "\(frameCount)f", active: isPreviewing)
            }
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Button {
                        captureMode = mode
                        statusText = "\(mode.rawValue) mode"
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundColor(captureMode == mode ? .black : .white)
                            .background(captureMode == mode ? Color.white : Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                CameraHUDPill(icon: "camera.aperture", text: qualityText, active: true)
                CameraHUDPill(icon: "camera.metering.center.weighted", text: lensText, active: true)
                CameraHUDPill(icon: "wand.and.stars", text: captureMode == .processed ? "Processed" : "Raw", active: captureMode == .processed)
                Spacer()
                Button {
                    showLab = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 32)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.black.opacity(0.28))
    }

    private var bottomDock: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(outputText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 18) {
                toolButton(systemName: isTorchOn ? "bolt.fill" : "bolt.slash", title: "Torch") {
                    toggleTorch()
                }
                toolButton(systemName: "arrow.triangle.2.circlepath.camera", title: "Flip") {
                    flipCamera()
                }
                shutterButton
                toolButton(systemName: "photo", title: "Photo") {
                    capturePhoto()
                }
                toolButton(systemName: "square.and.arrow.up", title: "Export") {
                    exportRecordedClip()
                }
            }
            HStack(spacing: 12) {
                Button {
                    startPreviewCamera()
                } label: {
                    Label(isPreviewing ? "Previewing" : "Start Preview", systemImage: "play.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundColor(.black)
                Button {
                    stopCamera()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 26)
        .background(.black.opacity(0.50))
    }

    private var shutterButton: some View {
        Button {
            if isRecording {
                stopCamera()
            } else {
                startRecordingCamera()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(isRecording ? Color.red : Color.white)
                    .frame(width: isRecording ? 38 : 62, height: isRecording ? 38 : 62)
                    .animation(.easeInOut(duration: 0.18), value: isRecording)
            }
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        }
        .buttonStyle(.plain)
    }

    private func toolButton(systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.72))
            }
            .foregroundColor(.white)
            .frame(width: 54)
        }
        .buttonStyle(.plain)
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
                    statusText = "Camera permission denied"
                    recentEventText = "Authorization failed"
                    return
                }
                do {
                    stopCameraWithoutFinishing()
                    let configuration = CameraCaptureConfiguration(
                        captureMode: .video,
                        preferredPosition: .back,
                        preferredDeviceTypes: [.wideAngle, .trueDepth],
                        video: .init(
                            sessionPreset: .high,
                            preferredFrameRateRange: .init(minimumFramesPerSecond: 24, maximumFramesPerSecond: 60),
                            preferredStabilizationMode: .auto
                        ),
                        photo: .init(deliversDepthData: true, deliversPortraitEffectsMatte: true),
                        advanced: .init(
                            metadataObjectTypes: [.face, .qr],
                            enablesDepthData: true,
                            enablesPortraitEffectsMatte: true
                        )
                    )
                    let engine = try KakaposSurface.camera(configuration: configuration)
                    let processors: [FrameProcessor] = captureMode == .processed
                        ? [HarbethExampleFrameProcessor(filters: [C7Contrast(contrast: 1.06), C7Exposure(exposure: 0.05)])]
                        : []
                    let previewController = engine.startPreview(
                        mode: captureMode == .processed ? .processed : .raw,
                        processors: processors,
                        callbackQueue: .main
                    ) { image, metadata in
                        frameCount += 1
                        previewImage = image
                        qualityText = "\(Int(image.width))x\(Int(image.height))"
                        recentEventText = "Frame \(frameCount) @ \(String(format: "%.2fs", metadata.presentationTime.seconds))"
                    }
                    engine.source.sessionEventHandler = { event in
                        DispatchQueue.main.async {
                            handleSessionEvent(event, recordingEnabled: recordingEnabled)
                        }
                    }
                    engine.source.photoCaptureHandler = { result in
                        DispatchQueue.main.async {
                            if let data = result.data, let image = UIImage(data: data)?.cgImage {
                                photoImage = image
                                previewImage = image
                            }
                            statusText = "Photo captured"
                            recentEventText = result.isFromCurrentFrame ? "Captured from current frame" : "Captured from photo output"
                        }
                    }
                    engine.advancedOutput.metadataObjectsHandler = { payload in
                        DispatchQueue.main.async {
                            recentEventText = "Metadata objects \(payload.objects.count)"
                        }
                    }
                    engine.advancedOutput.depthDataHandler = { _ in
                        DispatchQueue.main.async {
                            recentEventText = "Depth payload received"
                        }
                    }
                    self.engine = engine
                    self.previewController = previewController
                    self.recordingController = nil
                    self.previewImage = nil
                    self.photoImage = nil
                    self.player = nil
                    self.frameCount = 0
                    self.recordedDurationText = "00:00"
                    self.mediaStore.clearRecordedClip()
                    self.isPreviewing = true
                    self.isRecording = false
                    self.outputText = "Live camera"
                    self.statusText = recordingEnabled ? "Preparing recording" : "Preview running"
                    self.lensText = engine.deviceSnapshot.zoomFactorText
                    if recordingEnabled {
                        let outputURL = try FileManager.default.kaka.createURL(prefix: "showcase-camera", pathExtension: "mp4")
                        let recordingController = try engine.startRecording(
                            outputURL: outputURL,
                            processors: processors
                        )
                        recordingController.eventHandler = { event in
                            DispatchQueue.main.async {
                                handleRecordingEvent(event, recordingController: recordingController)
                            }
                        }
                        self.recordingController = recordingController
                        self.isRecording = true
                        self.statusText = "Recording"
                    }
                } catch {
                    statusText = "Camera failed"
                    recentEventText = error.localizedDescription
                }
            }
        }
        #else
        statusText = "Camera unavailable"
        recentEventText = "Requires UIKit camera environment"
        #endif
    }

    private func stopCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else {
            stopCameraWithoutFinishing()
            return
        }
        let wasRecording = isRecording
        engine.stopRecording { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let clip):
                    mediaStore.updateRecordedClip(clip)
                    if let url = clip.outputURL {
                        player = AVPlayer(url: url)
                        player?.play()
                        outputText = url.lastPathComponent
                    }
                    recordedDurationText = formatDuration(clip.duration)
                    statusText = wasRecording ? "Clip ready" : "Preview stopped"
                    recentEventText = "Ready for preview, export, or timeline"
                case .failure(let error):
                    statusText = "Stop failed"
                    recentEventText = error.localizedDescription
                }
            }
        }
        stopCameraWithoutFinishing()
        #else
        stopCameraWithoutFinishing()
        #endif
    }

    private func stopCameraWithoutFinishing() {
        #if canImport(UIKit) && !os(watchOS)
        engine?.stop()
        previewController = nil
        recordingController = nil
        engine = nil
        #endif
        isRecording = false
        isPreviewing = false
        previewImage = nil
        statusText = "Stopped"
    }

    private func capturePhoto() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else {
            startCamera(recordingEnabled: false)
            return
        }
        captureMode = .photo
        statusText = "Capturing photo"
        engine.capturePhoto()
        #else
        statusText = "Photo unavailable"
        #endif
    }

    private func flipCamera() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else {
            startCamera(recordingEnabled: false)
            return
        }
        if engine.switchCameraPosition() {
            statusText = "Camera switched"
            lensText = engine.deviceSnapshot.zoomFactorText
            recentEventText = "Position \(String(describing: engine.source.currentPosition))"
        } else {
            statusText = "Switch failed"
        }
        #else
        statusText = "Switch unavailable"
        #endif
    }

    private func toggleTorch() {
        #if canImport(UIKit) && !os(watchOS)
        guard let engine else {
            statusText = "Start camera first"
            return
        }
        do {
            isTorchOn.toggle()
            let snapshot = try engine.setTorchActive(isTorchOn)
            statusText = isTorchOn ? "Torch on" : "Torch off"
            recentEventText = snapshot.summaryText
        } catch {
            isTorchOn.toggle()
            statusText = "Torch unavailable"
            recentEventText = error.localizedDescription
        }
        #else
        statusText = "Torch unavailable"
        #endif
    }

    private func exportRecordedClip() {
        guard let clip = mediaStore.latestRecordedClip else {
            statusText = "No clip to export"
            recentEventText = "Record a clip first"
            return
        }
        do {
            let outputURL = try FileManager.default.kaka.createURL(prefix: "showcase-export", pathExtension: "mp4")
            guard let task = KakaposSurface.timelineExportTask(recordedClip: clip, outputURL: outputURL) else {
                statusText = "Export unavailable"
                return
            }
            clipExportTask = task
            statusText = "Exporting"
            recentEventText = "Timeline export started"
            task.start(complete: { result in
                DispatchQueue.main.async {
                    clipExportTask = nil
                    switch result {
                    case .success(let url):
                        player = AVPlayer(url: url)
                        player?.play()
                        outputText = url.lastPathComponent
                        statusText = "Export ready"
                        recentEventText = "Export completed"
                    case .failure(let error):
                        statusText = "Export failed"
                        recentEventText = error.localizedDescription
                    }
                }
            })
        } catch {
            statusText = "Export failed"
            recentEventText = error.localizedDescription
        }
    }

    private func handleSessionEvent(_ event: CameraSessionEvent, recordingEnabled: Bool) {
        switch event {
        case .willStart:
            recentEventText = "Starting session"
        case .didStart:
            recentEventText = recordingEnabled ? "Capture and recorder active" : "Live preview active"
        case .didPause:
            recentEventText = "Session paused"
        case .didResume:
            recentEventText = "Session resumed"
        case .didStop:
            recentEventText = "Session stopped"
        case .wasInterrupted, .wasInterruptedWhileRecording:
            statusText = "Interrupted"
            recentEventText = "Camera interruption"
        case .interruptionEnded:
            statusText = isRecording ? "Recording" : "Preview running"
            recentEventText = "Interruption ended"
        case .runtimeError(_, let description):
            statusText = "Runtime event"
            recentEventText = description ?? "Camera runtime event"
        case .willSwitchPosition(let position):
            recentEventText = "Switching \(String(describing: position))"
        case .positionChanged(let position):
            recentEventText = "Position \(String(describing: position))"
        case .authorizationChanged(let status):
            recentEventText = "Authorization \(status.description)"
        case .systemPressureChanged(let summary):
            recentEventText = summary
        case .audioRouteChanged(let route):
            recentEventText = route
        }
    }

    private func handleRecordingEvent(
        _ event: CameraRecordingEvent,
        recordingController: CameraRecordingController
    ) {
        switch event {
        case .willStart:
            statusText = "Preparing"
        case .didStart:
            statusText = "Recording"
            isRecording = true
        case .didPause:
            statusText = "Paused"
        case .didResume:
            statusText = "Recording"
        case .didFinish:
            statusText = "Finishing"
        case .didCancel:
            statusText = "Cancelled"
            isRecording = false
        case .didFail(let description):
            statusText = "Recording failed"
            recentEventText = description
        case .clipCompleted:
            recentEventText = "Clip completed"
        case .clipCountChanged(let count):
            recentEventText = "Segments \(count)"
        case .durationChanged(let duration):
            recordedDurationText = formatDuration(duration)
        case .droppedFrame(let reason):
            recentEventText = "Dropped frame \(reason)"
        }
        outputText = recordingController.recorderSink.summaryText
    }

    private func formatDuration(_ duration: CMTime) -> String {
        guard duration.seconds.isFinite else { return "00:00" }
        let totalSeconds = max(0, Int(duration.seconds.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct CameraHUDPill: View {
    let icon: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(active ? .black : .white)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(active ? Color.white : Color.white.opacity(0.14))
        .clipShape(Capsule())
    }
}

private struct CameraShowcasePlaceholder: View {
    let statusText: String

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.047)
            VStack(spacing: 18) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 58, weight: .thin))
                    .foregroundColor(.white.opacity(0.72))
                VStack(spacing: 6) {
                    Text("Camera SDK Preview")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.62))
                }
            }
        }
    }
}

private extension CameraDeviceSnapshot {
    var zoomFactorText: String {
        String(format: "%.1fx", zoomFactor)
    }
}
