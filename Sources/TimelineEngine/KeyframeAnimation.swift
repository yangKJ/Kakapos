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

    case cubicEaseIn
    case cubicEaseOut
    case cubicEaseInOut

    case quarticEaseIn
    case quarticEaseOut
    case quarticEaseInOut

    case quinticEaseIn
    case quinticEaseOut
    case quinticEaseInOut

    case sineEaseIn
    case sineEaseOut
    case sineEaseInOut

    case circularEaseIn
    case circularEaseOut
    case circularEaseInOut

    case exponentialEaseIn
    case exponentialEaseOut
    case exponentialEaseInOut

    case elasticEaseIn
    case elasticEaseOut
    case elasticEaseInOut

    case backEaseIn
    case backEaseOut
    case backEaseInOut

    case bounceEaseIn
    case bounceEaseOut
    case bounceEaseInOut

    public func value(at progress: Float) -> Float {
        let p = max(0, min(progress, 1))
        switch self {
        case .linear:
            return p

        case .easeIn:
            return p * p
        case .easeOut:
            return -(p * (p - 2))
        case .easeInOut:
            if p < 0.5 {
                return 2 * p * p
            } else {
                return (-2 * p * p) + (4 * p) - 1
            }

        case .cubicEaseIn:
            return p * p * p
        case .cubicEaseOut:
            let f = p - 1
            return f * f * f + 1
        case .cubicEaseInOut:
            if p < 0.5 {
                return 4 * p * p * p
            } else {
                let f = (2 * p) - 2
                return 0.5 * f * f * f + 1
            }

        case .quarticEaseIn:
            return p * p * p * p
        case .quarticEaseOut:
            let f = p - 1
            return f * f * f * (1 - p) + 1
        case .quarticEaseInOut:
            if p < 0.5 {
                return 8 * p * p * p * p
            } else {
                let f = p - 1
                return -8 * f * f * f * f + 1
            }

        case .quinticEaseIn:
            return p * p * p * p * p
        case .quinticEaseOut:
            let f = p - 1
            return f * f * f * f * f + 1
        case .quinticEaseInOut:
            if p < 0.5 {
                return 16 * p * p * p * p * p
            } else {
                let f = (2 * p) - 2
                return 0.5 * f * f * f * f * f + 1
            }

        case .sineEaseIn:
            return sin((p - 1) * Float.pi / 2) + 1
        case .sineEaseOut:
            return sin(p * Float.pi / 2)
        case .sineEaseInOut:
            return 0.5 * (1 - cos(p * Float.pi))

        case .circularEaseIn:
            return 1 - sqrt(1 - (p * p))
        case .circularEaseOut:
            return sqrt((2 - p) * p)
        case .circularEaseInOut:
            if p < 0.5 {
                return 0.5 * (1 - sqrt(1 - 4 * (p * p)))
            } else {
                return 0.5 * (sqrt(-((2 * p) - 3) * ((2 * p) - 1)) + 1)
            }

        case .exponentialEaseIn:
            return p == 0 ? p : pow(2, 10 * (p - 1))
        case .exponentialEaseOut:
            return p == 1 ? p : 1 - pow(2, -10 * p)
        case .exponentialEaseInOut:
            if p == 0 || p == 1 {
                return p
            }
            if p < 0.5 {
                return 0.5 * pow(2, (20 * p) - 10)
            } else {
                return -0.5 * pow(2, (-20 * p) + 10) + 1
            }

        case .elasticEaseIn:
            return sin(13 * Float.pi / 2 * p) * pow(2, 10 * (p - 1))
        case .elasticEaseOut:
            return sin(-13 * Float.pi / 2 * (p + 1)) * pow(2, -10 * p) + 1
        case .elasticEaseInOut:
            if p < 0.5 {
                return 0.5 * sin(13 * Float.pi / 2 * (2 * p)) * pow(2, 10 * ((2 * p) - 1))
            } else {
                return 0.5 * (sin(-13 * Float.pi / 2 * ((2 * p - 1) + 1)) * pow(2, -10 * (2 * p - 1)) + 2)
            }

        case .backEaseIn:
            return p * p * p - p * sin(p * Float.pi)
        case .backEaseOut:
            let f = 1 - p
            return 1 - (f * f * f - f * sin(f * Float.pi))
        case .backEaseInOut:
            if p < 0.5 {
                let f = 2 * p
                return 0.5 * (f * f * f - f * sin(f * Float.pi))
            } else {
                let f = 1 - (2 * p - 1)
                return 0.5 * (1 - (f * f * f - f * sin(f * Float.pi))) + 0.5
            }

        case .bounceEaseIn:
            return 1 - TimelineEasing.bounceEaseOut.value(at: 1 - p)
        case .bounceEaseOut:
            if p < 4 / 11.0 {
                return (121 * p * p) / 16.0
            } else if p < 8 / 11.0 {
                return (363 / 40.0 * p * p) - (99 / 10.0 * p) + 17 / 5.0
            } else if p < 9 / 10.0 {
                return (4356 / 361.0 * p * p) - (35442 / 1805.0 * p) + 16061 / 1805.0
            } else {
                return (54 / 5.0 * p * p) - (513 / 25.0 * p) + 268 / 25.0
            }
        case .bounceEaseInOut:
            if p < 0.5 {
                return 0.5 * TimelineEasing.bounceEaseIn.value(at: p * 2)
            } else {
                return 0.5 * TimelineEasing.bounceEaseOut.value(at: p * 2 - 1) + 0.5
            }
        }
    }
}

public struct KeyframeAnimation {
    public var keyPath: String
    public var values: [Float]
    public var keyTimes: [CMTime]
    public var timingFunctions: [TimelineEasing]

    public init(
        keyPath: String,
        values: [Float],
        keyTimes: [CMTime],
        easing: TimelineEasing = .linear
    ) {
        self.keyPath = keyPath
        self.values = values
        self.keyTimes = keyTimes
        self.timingFunctions = Array(
            repeating: easing,
            count: max(values.count - 1, 0)
        )
    }

    public init(
        keyPath: String,
        values: [Float],
        keyTimes: [CMTime],
        timingFunctions: [TimelineEasing]
    ) {
        self.keyPath = keyPath
        self.values = values
        self.keyTimes = keyTimes
        self.timingFunctions = timingFunctions
    }

    public var easing: TimelineEasing {
        get { timingFunctions.first ?? .linear }
        set {
            timingFunctions = Array(repeating: newValue, count: max(values.count - 1, 0))
        }
    }

    public func value(at time: CMTime) -> Float? {
        guard values.count == keyTimes.count, values.count > 0 else {
            return nil
        }
        if values.count == 1 {
            return values[0]
        }

        let timeValue = time.seconds
        for index in 0..<(keyTimes.count - 1) {
            let startTimeValue = keyTimes[index].seconds
            let endTimeValue = keyTimes[index + 1].seconds

            if index == 0 && timeValue < startTimeValue {
                return values[0]
            }

            if index == keyTimes.count - 2 && timeValue > endTimeValue {
                return values[index + 1]
            }

            if timeValue >= startTimeValue && timeValue <= endTimeValue {
                let progress = Float(timeValue - startTimeValue) / Float(max(endTimeValue - startTimeValue, 0.0001))
                let timingFunction = timingFunctions[safe: index] ?? timingFunctions.last ?? .linear
                let normalizedValue = timingFunction.value(at: progress)
                let fromValue = values[index]
                let toValue = values[index + 1]
                return fromValue + normalizedValue * (toValue - fromValue)
            }
        }

        return nil
    }

    public static func value(for keyPath: String, at time: CMTime, animations: [KeyframeAnimation]) -> Float? {
        for animation in animations where animation.keyPath == keyPath {
            if let value = animation.value(at: time) {
                return value
            }
        }
        return nil
    }
}

public protocol TimelineAnimatable {
    var animations: [KeyframeAnimation]? { get set }
    mutating func updateAnimationValues(at time: CMTime)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
