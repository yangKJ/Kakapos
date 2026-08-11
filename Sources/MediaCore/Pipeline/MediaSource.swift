//
//  MediaSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

/// 控制实时 source 向异步 processor/sink 链路提交帧时的在途上限。
/// 离线、不可丢帧的媒体处理应继续使用 `.unbounded`。
public enum MediaSourceDeliveryPolicy: Equatable, Sendable {
    case unbounded
    case latestOnly
    case boundedDropNewest(maximumInFlightFrames: Int)

    var normalizedMaximumInFlightFrames: Int? {
        switch self {
        case .unbounded:
            return nil
        case .latestOnly:
            return 1
        case .boundedDropNewest(let maximumInFlightFrames):
            return max(1, maximumInFlightFrames)
        }
    }
}

public protocol MediaSourceDelegate: AnyObject {
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame)
    func mediaSource(_ source: MediaSource, didFail error: Error)
    func mediaSourceDidFinish(_ source: MediaSource)
}

public extension MediaSourceDelegate {
    func mediaSource(_ source: MediaSource, didFail error: Error) {}
    func mediaSourceDidFinish(_ source: MediaSource) {}
}

/// 允许同一个实时 source 同时为多个独立 pipeline 提供回调。
///
/// 普通 source 仍可只实现 `MediaSource.delegate`；只有明确支持并行分支的
/// source 才需要实现该合同，并应以弱引用保存注册的 delegate。
public protocol MediaSourceDelegateMultiplexing: AnyObject {
    func addMediaSourceDelegate(_ delegate: MediaSourceDelegate)
    func removeMediaSourceDelegate(_ delegate: MediaSourceDelegate)
}

public protocol MediaSource: AnyObject {
    var delegate: MediaSourceDelegate? { get set }
    func start()
    func pause()
    func resume()
    func stop()
    func cancel()
}
