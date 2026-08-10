//
//  PreviewShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import Kakapos
import SwiftUI

struct PreviewShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.058).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    previewRoute
                    recordedClipPanel
                    surfacePanel
                }
                .padding(20)
            }
        }
        .navigationTitle("Preview Pipeline")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview Pipeline")
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
            Text("Player frames and recorded clips both route through KakaposSurface.preview into the same preview sink contract.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewRoute: some View {
        NavigationLink {
            PlayerPreviewView(mediaStore: mediaStore)
        } label: {
            ShowcaseRouteCard(
                icon: "play.rectangle",
                title: "Open Preview Demo",
                subtitle: "Inspect player-frame pulls, recorded clip preview, seek behavior, and processed output through the example-owned Harbeth adapter.",
                accent: .orange
            )
        }
        .buttonStyle(.plain)
    }

    private var recordedClipPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded Clip Re-entry")
                .font(.headline)
                .foregroundColor(.white)
            Text(mediaStore.latestRecordedClipSummaryText)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                HandoffPill(icon: "clock.arrow.circlepath", text: "Seek")
                HandoffPill(icon: "photo.on.rectangle", text: "PreviewSink")
                HandoffPill(icon: "wand.and.stars", text: "Processed")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var surfacePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Surface Path")
                .font(.headline)
                .foregroundColor(.white)
            Text("KakaposSurface.preview(player:processors:callbackQueue:handler:) and KakaposSurface.preview(recordedClip:...) are the primary preview entry points.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
