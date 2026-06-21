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

    public init(kind: Kind = .crossDissolve, timeRange: CMTimeRange) {
        self.kind = kind
        self.timeRange = timeRange
    }
}
