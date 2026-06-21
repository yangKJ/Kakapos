//
//  Transition.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public struct Transition {
    public enum Kind {
        case crossDissolve
    }

    public var kind: Kind
    public var timeRange: CMTimeRange
    public var sourceLayerLevel: Int?
    public var destinationLayerLevel: Int?

    public init(
        kind: Kind = .crossDissolve,
        timeRange: CMTimeRange,
        sourceLayerLevel: Int? = nil,
        destinationLayerLevel: Int? = nil
    ) {
        self.kind = kind
        self.timeRange = timeRange
        self.sourceLayerLevel = sourceLayerLevel
        self.destinationLayerLevel = destinationLayerLevel
    }
}
