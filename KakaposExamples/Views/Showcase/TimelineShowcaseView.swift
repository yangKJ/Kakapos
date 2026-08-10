//
//  TimelineShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import Kakapos
import SwiftUI

struct TimelineShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.058).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    timelineRoute
                    featurePanel
                    clipPanel
                }
                .padding(20)
            }
        }
        .navigationTitle("Timeline Engine")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline Engine")
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
            Text("Layer clips, images, effects, transitions, and audio mix, then compile the result into preview or export planning.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timelineRoute: some View {
        NavigationLink {
            TimelineExportView(mediaStore: mediaStore)
        } label: {
            ShowcaseRouteCard(
                icon: "timeline.selection",
                title: "Open Timeline Demo",
                subtitle: "Compile layered media, preview the rendered composition, and promote recorded clips into timeline export.",
                accent: .pink
            )
        }
        .buttonStyle(.plain)
    }

    private var featurePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compile Targets")
                .font(.headline)
                .foregroundColor(.white)
            Text("TimelineComposition compiles to composition, videoComposition, audioMix, render instructions, and render plan. Showcase routes stay on KakaposSurface.timeline and KakaposSurface.timelineExportTask.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                HandoffPill(icon: "arrow.triangle.branch", text: "Transitions")
                HandoffPill(icon: "waveform", text: "Audio Mix")
                HandoffPill(icon: "slider.horizontal.below.rectangle", text: "Keyframes")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var clipPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded Clip Entry")
                .font(.headline)
                .foregroundColor(.white)
            Text("Latest clip: \(mediaStore.latestRecordedClipFilename)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))
            Text("Use KakaposSurface.timeline(recordedClip:) to promote captured media directly into timeline planning.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
