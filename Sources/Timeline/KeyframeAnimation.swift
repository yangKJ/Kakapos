//
//  KeyframeAnimation.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public struct KeyframeAnimation {
    public var keyPath: String
    public var values: [Float]
    public var keyTimes: [CMTime]

    public init(keyPath: String, values: [Float], keyTimes: [CMTime]) {
        self.keyPath = keyPath
        self.values = values
        self.keyTimes = keyTimes
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
                return values[index] + (values[index + 1] - values[index]) * progress
            }
        }
        return values.last
    }
}
