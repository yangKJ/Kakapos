//
//  MediaSourceSnapshot.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public struct MediaSourceSnapshot {
    public let stateDescription: String
    public let lastFrameIndex: Int64?
    public let lastPresentationTime: CMTime?
    public let lastSourceTime: CMTime?
    public let lastErrorDescription: String?
    public let details: [String: String]

    public init(
        stateDescription: String,
        lastFrameIndex: Int64? = nil,
        lastPresentationTime: CMTime? = nil,
        lastSourceTime: CMTime? = nil,
        lastErrorDescription: String? = nil,
        details: [String: String] = [:]
    ) {
        self.stateDescription = stateDescription
        self.lastFrameIndex = lastFrameIndex
        self.lastPresentationTime = lastPresentationTime
        self.lastSourceTime = lastSourceTime
        self.lastErrorDescription = lastErrorDescription
        self.details = details
    }

    public var summaryText: String {
        var parts: [String] = ["state \(stateDescription)"]
        if let lastFrameIndex {
            parts.append("frame \(lastFrameIndex)")
        }
        if let lastPresentationTime {
            parts.append("presentation \(String(format: "%.2fs", lastPresentationTime.seconds))")
        }
        if let lastSourceTime {
            parts.append("sourceTime \(String(format: "%.2fs", lastSourceTime.seconds))")
        }
        for key in details.keys.sorted() {
            if let value = details[key] {
                parts.append("\(key) \(value)")
            }
        }
        if let lastErrorDescription {
            parts.append("error \(lastErrorDescription)")
        }
        return parts.joined(separator: " · ")
    }
}

public protocol MediaSourceSnapshotProviding: AnyObject {
    var sourceSnapshot: MediaSourceSnapshot { get }
}
