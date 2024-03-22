//
//  TimeRangeType.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation
import AVFoundation

public enum TimeRangeType {
    
    case start(CGFloat)
    
    case end(CGFloat)
    
    case range(ClosedRange<CGFloat>)
    
    case startAndEnd(CGFloat, CGFloat)
}

extension TimeRangeType {
    
    func minTime() -> CGFloat {
        switch self {
        case .start(let seconds):
            return max(0, seconds)
        case .end:
            return 0
        case .range(let range):
            return max(0, range.lowerBound)
        case .startAndEnd(let seconds, _):
            return max(0, seconds)
        }
    }
    
    func timeRange(duration: CMTime) -> CMTimeRange? {
        let seconds = duration.seconds
        switch self {
        case .start(let time):
            return TimeRangeType.range(time...seconds).timeRange(duration: duration)
        case .end(let time):
            return TimeRangeType.range(0...(seconds-time)).timeRange(duration: duration)
        case .startAndEnd(let time1, let time2):
            return TimeRangeType.range(time1...(seconds-time2)).timeRange(duration: duration)
        case .range(let range):
            if range.lowerBound >= seconds || (range.upperBound - range.lowerBound) >= seconds {
                return nil
            }
            let time = max(0, range.lowerBound)
            let max = min(seconds, range.upperBound)
            let s = CMTimeMakeWithSeconds(time, preferredTimescale: duration.timescale)
            let d = CMTimeMakeWithSeconds(max - time, preferredTimescale: duration.timescale)
            return CMTimeRangeMake(start: s, duration: d)
        }
    }
}
