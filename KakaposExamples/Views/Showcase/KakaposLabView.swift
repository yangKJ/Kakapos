//
//  KakaposLabView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI

struct KakaposLabView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        NavigationView {
            KakaposLabRoutesView(mediaStore: mediaStore)
            .navigationTitle("Kakapos Lab")
        }
        #if !os(macOS)
        .navigationViewStyle(.stack)
        #endif
    }
}

struct KakaposLabRoutesView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        List {
            Section("Labs") {
                NavigationLink {
                    CameraRecordView(mediaStore: mediaStore)
                } label: {
                    LabRouteRow(
                        title: "Camera Lab",
                        subtitle: "Session state, preview sink summary, recorder diagnostics, and lower-level controls.",
                        icon: "camera.viewfinder"
                    )
                }
                NavigationLink {
                    OfflineExportView(mediaStore: mediaStore)
                } label: {
                    LabRouteRow(
                        title: "Export Lab",
                        subtitle: "Offline export task state, progress snapshots, save flow, and cancellation.",
                        icon: "square.and.arrow.up"
                    )
                }
                NavigationLink {
                    PlayerPreviewView(mediaStore: mediaStore)
                } label: {
                    LabRouteRow(
                        title: "Preview Lab",
                        subtitle: "Player frame pulls, seek behavior, generation resets, and preview sink inspection.",
                        icon: "play.rectangle"
                    )
                }
                NavigationLink {
                    TimelineExportView(mediaStore: mediaStore)
                } label: {
                    LabRouteRow(
                        title: "Timeline Lab",
                        subtitle: "Compile layered compositions, transitions, keyframes, and audio mix planning.",
                        icon: "timeline.selection"
                    )
                }
            }
        }
    }
}

private struct LabRouteRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
