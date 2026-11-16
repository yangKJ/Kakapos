// 作者：Condy

import Foundation
import AVFoundation

/// 按时间推进活动集合；随机向前缩短或向后查询时重置游标。
struct TimelineIntervalIndex<Element> {
    private struct Entry {
        let element: Element
        let range: CMTimeRange
        let level: Int
        let order: Int
    }

    private let entries: [Entry]
    private var cursor = 0
    private var active: [Entry] = []
    private var previousRange: CMTimeRange?

    init(_ elements: [Element], range: (Element) -> CMTimeRange, level: (Element) -> Int) {
        entries = elements.enumerated().map {
            Entry(element: $0.element, range: range($0.element), level: level($0.element), order: $0.offset)
        }.sorted {
            $0.range.start == $1.range.start ? $0.order < $1.order : $0.range.start < $1.range.start
        }
    }

    mutating func elements(overlapping range: CMTimeRange) -> [Element] {
        if let previousRange, range.start < previousRange.start || range.end < previousRange.end {
            cursor = 0
            active.removeAll(keepingCapacity: true)
        }
        previousRange = range
        active.removeAll { $0.range.end <= range.start }
        while cursor < entries.count && entries[cursor].range.start < range.end {
            let entry = entries[cursor]
            cursor += 1
            guard entry.range.end > range.start else { continue }
            var low = 0
            var high = active.count
            while low < high {
                let middle = (low + high) / 2
                let candidate = active[middle]
                if candidate.level < entry.level || (candidate.level == entry.level && candidate.order < entry.order) {
                    low = middle + 1
                } else { high = middle }
            }
            active.insert(entry, at: low)
        }
        return active.map(\.element)
    }
}

struct TimelineKeyframeIndex {
    private let animations: [String: [KeyframeAnimation]]
    private var cursors: [String: [Int]] = [:]

    init(_ animations: [KeyframeAnimation]) {
        self.animations = Dictionary(grouping: animations, by: \.keyPath)
    }

    func value(for keyPath: String, at time: CMTime) -> Float? {
        animations[keyPath]?.lazy.compactMap { $0.value(at: time) }.first
    }
    mutating func sampledValue(for keyPath: String, at time: CMTime) -> Float? {
        guard let curves = animations[keyPath] else { return nil }
        var positions = cursors[keyPath] ?? Array(repeating: 0, count: curves.count)
        defer { cursors[keyPath] = positions }
        for (index, curve) in curves.enumerated() {
            if let value = curve.value(at: time, cursor: &positions[index]) { return value }
        }
        return nil
    }

}

enum TimelineCurveSampling {
    static func progress(at time: CMTime, in range: CMTimeRange) -> Float {
        guard range.duration.isNumeric, range.duration > .zero else { return 0 }
        return Float(max(0, min((time - range.start).seconds / range.duration.seconds, 1)))
    }

    /// 四分位检测避免端点及中点重合时漏掉回弹和完整旋转。
    static func times(
        in range: CMTimeRange,
        minimumStep: CMTime,
        tolerance: Double = 0.001,
        evaluate: (CMTime) -> [Double]
    ) -> [CMTime] {
        guard range.start.isNumeric, range.end.isNumeric, range.duration > .zero else {
            return [range.start, range.end]
        }
        var result = [range.start]
        func appendSegment(_ start: CMTime, _ end: CMTime, _ from: [Double], _ to: [Double], _ depth: Int) {
            let duration = end - start
            guard depth < 12, duration > minimumStep else { result.append(end); return }
            let points = [0.25, 0.5, 0.75].map { start + CMTimeMultiplyByFloat64(duration, multiplier: $0) }
            let values = points.map(evaluate)
            let needsSplit = values.enumerated().contains { offset, value in
                let fraction = Double(offset + 1) / 4
                return zip(value, zip(from, to)).contains { actual, endpoints in
                    abs(actual - (endpoints.0 + (endpoints.1 - endpoints.0) * fraction)) > tolerance
                }
            }
            guard needsSplit, points[1] > start, points[1] < end else { result.append(end); return }
            appendSegment(start, points[1], from, values[1], depth + 1)
            appendSegment(points[1], end, values[1], to, depth + 1)
        }
        appendSegment(range.start, range.end, evaluate(range.start), evaluate(range.end), 0)
        return result
    }
}
