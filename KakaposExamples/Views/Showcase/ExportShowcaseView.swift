//
//  ExportShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI

struct ExportShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.058).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    exportRoute
                    pipelinePanel
                    clipPanel
                }
                .padding(20)
            }
        }
        .navigationTitle("Export Board")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Board")
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
            Text("Use one surface entry for asset export and recorded clip export, then choose between legacy asset session or reader/writer execution.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exportRoute: some View {
        NavigationLink {
            OfflineExportView(mediaStore: mediaStore)
        } label: {
            ShowcaseRouteCard(
                icon: "square.and.arrow.up",
                title: "Open Export Demo",
                subtitle: "Run offline export, monitor progress, cancel tasks, save output, and export the latest recorded clip through the timeline bridge.",
                accent: .green
            )
        }
        .buttonStyle(.plain)
    }

    private var pipelinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution Paths")
                .font(.headline)
                .foregroundColor(.white)
            Text("KakaposSurface.exportTask starts from one public path. Under that surface, VideoX can still use AVAssetExportSession or ReaderWriterExportJob depending on the configured export pipeline.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                HandoffPill(icon: "shippingbox", text: "Asset")
                HandoffPill(icon: "dial.high", text: "Progress")
                HandoffPill(icon: "pause.circle", text: "Cancel")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var clipPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded Clip Handoff")
                .font(.headline)
                .foregroundColor(.white)
            Text("Latest clip: \(mediaStore.latestRecordedClipFilename)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))
            Text(mediaStore.latestRecordedClipSummaryText)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
