//
//  HDRContractLabView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/10/7.
//

import AVFoundation
import AVKit
import Kakapos
import SwiftUI
import UniformTypeIdentifiers

struct HDRContractLabView: View {
    @StateObject private var model = HDRContractLabModel()
    @State private var choosesMedia = false
    @State private var policy = VideoExportColorPolicy.hdrHLG

    var body: some View {
        Form {
            Section("输入与输出") {
                Text(model.sourceURL?.lastPathComponent ?? "请选择视频素材")
                Button("选择视频") { choosesMedia = true }
                Picker("输出色彩", selection: $policy) {
                    Text("SDR · BT.709").tag(VideoExportColorPolicy.standardBT709)
                    Text("HDR · HLG").tag(VideoExportColorPolicy.hdrHLG)
                    Text("HDR · PQ").tag(VideoExportColorPolicy.hdrPQ)
                }
                Button("验证时间段效果并导出") { model.export(policy: policy) }
                    .disabled(model.sourceURL == nil || model.isExporting)
                Button("暂停 / 继续") { model.togglePause() }
                    .disabled(model.job == nil)
                Button("取消当前导出") { model.cancel() }
                    .disabled(model.job == nil)
            }
            Section("实际产物") {
                ProgressView(value: model.progress)
                Text(model.status).font(.footnote)
                if let player = model.player {
                    VideoPlayer(player: player).frame(height: 260)
                }
                if let output = model.outputURL { ShareLink(item: output) { Text("分享验收产物") } }
            }
            Section("本场景合同") {
                Text("效果只覆盖视频中间三分之一，强度为 0.5。处理器使用恒等变换，以独立核对时间段调度、线性光混合、音轨和 HDR 编码；画面变化由其他既有滤镜场景验收。")
                    .font(.footnote)
            }
        }
        .navigationTitle("HDR 与时间段效果验收")
        .fileImporter(isPresented: $choosesMedia, allowedContentTypes: [.movie]) { result in
            model.select(result)
        }
        .onDisappear { model.pause() }
    }
}

@MainActor
private final class HDRContractLabModel: ObservableObject {
    @Published var sourceURL = Bundle.main.url(forResource: "IMG_3156", withExtension: "MOV")
    @Published var outputURL: URL?
    @Published var player: AVPlayer?
    @Published var progress: Float = 0
    @Published var status = "尚未执行验收"
    @Published var isExporting = false
    var job: ReaderWriterExportJob?

    func select(_ result: Result<URL, Error>) {
        do {
            let selected = try result.get()
            let accesses = selected.startAccessingSecurityScopedResource()
            defer { if accesses { selected.stopAccessingSecurityScopedResource() } }
            let copied = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(selected.pathExtension)
            try FileManager.default.copyItem(at: selected, to: copied)
            sourceURL = copied
            status = "素材已准备"
        } catch { status = error.localizedDescription }
    }

    func export(policy: VideoExportColorPolicy) {
        guard let sourceURL else { return }
        let asset = AVAsset(url: sourceURL)
        let duration = asset.duration
        guard duration.isNumeric, duration.seconds > 0 else {
            status = "素材时长无效"
            return
        }
        let clip = ClipLayer(
            asset: asset, timeRange: CMTimeRange(start: .zero, duration: duration),
            sourceTimeRange: CMTimeRange(start: .zero, duration: duration))
        let range = CMTimeRange(
            start: CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / 3),
            duration: CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / 3))
        let effect = EffectLayer(
            timeRange: range, source: EffectSource(makeProcessor: { PassthroughFrameProcessor() }, intensity: 0.5))
        let size = asset.tracks(withMediaType: .video).first?.naturalSize ?? CGSize(width: 1920, height: 1080)
        let pipeline = TimelinePipeline(renderSize: size, layers: [clip, effect])
        let compiled = pipeline.compile(exportProfile: .init(videoCodec: .hevc, colorPolicy: policy))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let task = compiled.makeExportJob(outputURL: output)
        job = task
        isExporting = true
        progress = 0
        status = "正在处理，完成后检查实际编码产物"
        task.progressHandler = { [weak self] info in
            DispatchQueue.main.async { self?.progress = Float(info.fractionCompleted) }
        }
        task.export { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false
                self.job = nil
                do {
                    let url = try result.get()
                    let profile = try VideoAssetProfileInspector().inspect(AVAsset(url: url))
                    guard profile.frameFormat.dynamicRange == policy.requestedDynamicRange else {
                        throw VideoExportProfileError.invalidHDROutput
                    }
                    self.outputURL = url
                    self.player = AVPlayer(url: url)
                    self.status =
                        "实际产物：\(profile.videoCodec)，\(profile.frameFormat.dynamicRange)，音轨 \(profile.audioTrackCount)，时长 \(String(format: "%.2f", profile.duration.seconds)) 秒"
                } catch { self.status = "未通过：\(error.localizedDescription)" }
            }
        }
    }

    func togglePause() {
        if job?.status == .paused { job?.resume() } else { job?.pause() }
    }

    func pause() {
        player?.pause()
        job?.pause()
    }
    func cancel() { job?.cancel() }
}
