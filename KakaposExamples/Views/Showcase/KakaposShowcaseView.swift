//
//  KakaposShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import SwiftUI

struct KakaposShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.055, blue: 0.065).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        workflowPanel
                        boardGrid
                        apiPanel
                        clipHandoffPanel
                        labPanel
                    }
                    .padding(20)
                }
            }
            #if !os(macOS)
            .navigationBarHidden(true)
            #endif
        }
        #if !os(macOS)
        .navigationViewStyle(.stack)
        #endif
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kakapos Media Engine")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Camera capture, processed preview, recording, offline export, and timeline composition over one surface-first API.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(.white)
                    .frame(width: 74, height: 74)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 8) {
                ShowcaseBadge(text: "Surface-first", icon: "square.stack.3d.up")
                ShowcaseBadge(text: "Processor-neutral", icon: "wand.and.rays")
                ShowcaseBadge(text: "Harbeth-ready", icon: "circle.grid.cross")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.19, blue: 0.22),
                    Color(red: 0.07, green: 0.08, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workflow")
                .font(.headline)
                .foregroundColor(.white)
            HStack(spacing: 10) {
                WorkflowStep(title: "Capture", icon: "camera")
                WorkflowArrow()
                WorkflowStep(title: "Preview", icon: "play.rectangle")
                WorkflowArrow()
                WorkflowStep(title: "Export", icon: "square.and.arrow.up")
                WorkflowArrow()
                WorkflowStep(title: "Timeline", icon: "timeline.selection")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var boardGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Showcase")
                .font(.headline)
                .foregroundColor(.white)
            VStack(spacing: 12) {
                NavigationLink {
                    CameraShowcaseView(mediaStore: mediaStore)
                } label: {
                    ShowcaseRouteCard(
                        icon: "camera.aperture",
                        title: "Camera Engine",
                        subtitle: "Live camera, processed preview, device controls, recording, and advanced capture outputs.",
                        accent: .cyan
                    )
                }
                NavigationLink {
                    PreviewShowcaseView(mediaStore: mediaStore)
                } label: {
                    ShowcaseRouteCard(
                        icon: "play.rectangle",
                        title: "Preview Pipeline",
                        subtitle: "Pull frames from player or recorded media through KakaposSurface.preview and inspect the processed output.",
                        accent: .orange
                    )
                }
                NavigationLink {
                    ExportShowcaseView(mediaStore: mediaStore)
                } label: {
                    ShowcaseRouteCard(
                        icon: "square.and.arrow.up",
                        title: "Export Board",
                        subtitle: "Run offline export from a single KakaposSurface entry, with progress, cancellation, and recorded clip handoff.",
                        accent: .green
                    )
                }
                NavigationLink {
                    TimelineShowcaseView(mediaStore: mediaStore)
                } label: {
                    ShowcaseRouteCard(
                        icon: "timeline.selection",
                        title: "Timeline Engine",
                        subtitle: "Compile layered timelines with transitions, audio mix, keyframes, and direct export planning.",
                        accent: .pink
                    )
                }
            }
        }
    }

    private var apiPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Public API")
                .font(.headline)
                .foregroundColor(.white)
            Text("Recommended entry")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.56))
            Text("KakaposSurface")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text("The showcase and README now route through KakaposSurface. KakaposBoards remains a deprecated compatibility alias, not the primary path.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            SurfaceSnippetCard()
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var clipHandoffPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Clip")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(mediaStore.latestRecordedClipFilename)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.54))
                    .lineLimit(1)
            }
            Text(mediaStore.latestRecordedClipSummaryText)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                HandoffPill(icon: "play.rectangle", text: "Preview")
                HandoffPill(icon: "timeline.selection", text: "Timeline")
                HandoffPill(icon: "square.and.arrow.up", text: "Export")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var labPanel: some View {
        NavigationLink {
            KakaposLabRoutesView(mediaStore: mediaStore)
                .navigationTitle("Kakapos Lab")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Labs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Raw state, diagnostics, event text, and lower-level verification live in the lab layer, not the showcase.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ShowcaseRouteCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.22))
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accent)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ShowcaseBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.14))
        .clipShape(Capsule())
    }
}

struct HandoffPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct WorkflowStep: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkflowArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.42))
            .padding(.top, -10)
    }
}

private struct SurfaceSnippetCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("let preview = KakaposSurface.preview(player: player) { image, metadata in }")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("let camera = try KakaposSurface.camera(configuration: .init())")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("let timeline = KakaposSurface.timeline(recordedClip: clip)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
