//
//  CameraPreviewSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import KakaposVideo
import CoreGraphics

public final class CameraPreviewSink {
    public let sink: PreviewSink

    public init(sink: PreviewSink) {
        self.sink = sink
    }

    public var state: PreviewSink.State {
        sink.state
    }

    public var snapshot: PreviewSink.Snapshot {
        sink.snapshot
    }

    public var summary: PreviewSink.Summary {
        sink.summary
    }

    public var summaryText: String {
        sink.summaryText
    }

    public var lastFrame: MediaFrame? {
        sink.lastFrame
    }

    public var lastImage: CGImage? {
        sink.lastImage
    }
}
