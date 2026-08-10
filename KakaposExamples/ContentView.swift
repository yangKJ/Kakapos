//
//  ContentView.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import Kakapos
import SwiftUI

final class ExampleAppState: ObservableObject {
    @Published private(set) var latestRecordedClip: RecordedClip?
    @Published private(set) var latestRecordedClipSummaryText = "No recorded clip yet"
    @Published private(set) var latestRecordedClipFilename = "none"

    func updateRecordedClip(_ clip: RecordedClip?) {
        latestRecordedClip = clip
        latestRecordedClipSummaryText = clip?.summaryText ?? "No recorded clip yet"
        latestRecordedClipFilename = clip?.outputURL?.lastPathComponent ?? "none"
    }

    func clearRecordedClip() {
        updateRecordedClip(nil)
    }
}

struct ContentView: View {
    @StateObject private var mediaStore = ExampleAppState()

    var body: some View {
        TabView {
            KakaposShowcaseView(mediaStore: mediaStore)
                .tabItem { Label("Showcase", systemImage: "sparkles.rectangle.stack") }
            KakaposLabView(mediaStore: mediaStore)
                .tabItem { Label("Lab", systemImage: "slider.horizontal.3") }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
