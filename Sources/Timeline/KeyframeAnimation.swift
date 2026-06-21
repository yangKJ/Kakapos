//
//  KeyframeAnimation.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public enum TimelineEasing: Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    func apply(to progress: Float) -> Float {
        let clamped = max(0, min(progress, 1))
        switch self {
        case .linear:
            return clamped
        case .easeIn:
            return clamped * clamped
        case .easeOut:
            let inverse = 1 - clamped
            return 1 - (inverse * inverse)
        case .easeInOut:
            if clamped < 0.5 {
                return 2 * clamped * clamped
            }
            let inverse = -2 * clamped + 2
            return 1 - ((inverse * inverse) / 2)
        }
    }
}

public struct KeyframeAnimation {
    public var keyPath: String
    public var values: [Float]
    public var keyTimes: [CMTime]
    public var easing: TimelineEasing

    public init(keyPath: String, values: [Float], keyTimes: [CMTime], easing: TimelineEasing = .linear) {
        self.keyPath = keyPath
        self.values = values
        self.keyTimes = keyTimes
        self.easing = easing
    }

    public func value(at time: CMTime) -> Float? {
        guard values.count == keyTimes.count, values.count > 0 else { return nil }
        guard values.count > 1 else { return values.first }
        let seconds = time.seconds
        for index in 0..<(keyTimes.count - 1) {
            let start = keyTimes[index].seconds
            let end = keyTimes[index + 1].seconds
            if seconds <= start { return values[index] }
            if seconds >= start && seconds <= end {
                let progress = Float((seconds - start) / max(end - start, 0.0001))
                let eased = easing.apply(to: progress)
                return values[index] + (values[index + 1] - values[index]) * eased
            }
        }
        return values.last
    }

    public static func value(for keyPath: String, at time: CMTime, animations: [KeyframeAnimation]) -> Float? {
        animations.first(where: { $0.keyPath == keyPath })?.value(at: time)
    }
}
