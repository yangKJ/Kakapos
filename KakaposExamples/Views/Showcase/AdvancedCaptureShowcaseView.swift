//
//  AdvancedCaptureShowcaseView.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import Kakapos
import SwiftUI

struct AdvancedCaptureShowcaseView: View {
    @ObservedObject var mediaStore: ExampleAppState

    private let capabilities: [AdvancedCaptureCapability] = [
        .init(icon: "face.smiling", title: "Metadata Objects", status: "Live overlay", summary: "Face and QR detection events can be routed through CameraAdvancedOutput."),
        .init(icon: "circle.hexagongrid", title: "Depth Data", status: "Capability gated", summary: "Depth payloads stay optional and never break the main preview or record chain."),
        .init(icon: "person.crop.rectangle", title: "Portrait Matte", status: "Photo + stream", summary: "Portrait effects matte data is surfaced as a typed camera payload when available."),
        .init(icon: "arkit", title: "AR Frames", status: "Platform gated", summary: "AR frame routing is separated from normal camera capture and safely degrades when unavailable."),
        .init(icon: "rectangle.split.2x1", title: "MultiCam", status: "Device gated", summary: "Front and back branches are modeled independently for future preview and recording routing.")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.058).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    liveAdvancedEntry
                    capabilityList
                    fallbackPanel
                }
                .padding(20)
            }
        }
        .navigationTitle("Advanced Capture")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Capture")
                .font(.system(size: 31, weight: .bold))
                .foregroundColor(.white)
            Text("Optional camera outputs are exposed as typed payloads, with stable fallback on unsupported devices.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveAdvancedEntry: some View {
        NavigationLink {
            CameraShowcaseView(mediaStore: mediaStore)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.mint)
                    .frame(width: 62, height: 62)
                    .background(Color.mint.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Run Advanced Camera")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Open the live camera with processed preview, metadata, depth, and portrait capture requests enabled.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var capabilityList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capability Gates")
                .font(.headline)
                .foregroundColor(.white)
            ForEach(capabilities) { capability in
                AdvancedCaptureCapabilityRow(capability: capability)
            }
        }
    }

    private var fallbackPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.green)
                Text("Safe Fallback Contract")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text("Unsupported advanced outputs should become disabled badges or unsupported snapshots. The base preview and recording path should continue to run.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AdvancedCaptureCapability: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let status: String
    let summary: String
}

private struct AdvancedCaptureCapabilityRow: View {
    let capability: AdvancedCaptureCapability

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: capability.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.mint)
                .frame(width: 44, height: 44)
                .background(Color.mint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(capability.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(capability.status)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.mint)
                        .clipShape(Capsule())
                }
                Text(capability.summary)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
