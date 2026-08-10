//
//  RecordingStudioShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI
import AVKit
import Kakapos

struct RecordingStudioShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.047, blue: 0.055).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    liveEntry
                    resultPanel
                    handoffPanel
                }
                .padding(20)
            }
        }
        .navigationTitle("Recording Studio")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let url = mediaStore.latestRecordedClip?.outputURL {
                player = AVPlayer(url: url)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording Studio")
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
            Text("Capture once, then keep the media inside Kakapos for preview, export, and timeline composition.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveEntry: some View {
        NavigationLink {
            CameraShowcaseView(mediaStore: mediaStore)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black)
                    .frame(height: 250)
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 58, weight: .thin))
                                .foregroundColor(.red)
                            Text("Open Full-Screen Recorder")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    )
                HStack {
                    Label("Preview + Record + Process", systemImage: "camera.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.64))
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Take")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(mediaStore.latestRecordedClipFilename)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onAppear { player.play() }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 160)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "film")
                                .font(.system(size: 34, weight: .light))
                                .foregroundColor(.white.opacity(0.72))
                            Text("No recorded clip yet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    )
            }
            Text(mediaStore.latestRecordedClipSummaryText)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var handoffPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Product Handoff")
                .font(.headline)
                .foregroundColor(.white)
            VStack(spacing: 10) {
                RecordingHandoffRow(icon: "play.rectangle", title: "Preview result", subtitle: "Build a player preview from the recorded clip.")
                RecordingHandoffRow(icon: "timeline.selection", title: "Promote to timeline", subtitle: "Use the clip as a first-class timeline source.")
                RecordingHandoffRow(icon: "square.and.arrow.up", title: "Export immediately", subtitle: "Send the same clip into the export board without extra conversion.")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RecordingHandoffRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
