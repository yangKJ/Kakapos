// 作者：Condy
import Foundation
import KakaposMediaCore

/// 内部有界订阅者拥有各自槽位；未声明背压的外部订阅者继续占用源入口预算。
enum CameraFrameDistributor {
    static func deliver(
        _ frame: MediaFrame,
        source: MediaSource,
        delegates: [MediaSourceDelegate],
        output: MediaOutputNode,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping () -> Void
    ) {
        var group: DispatchGroup?
        func waitingGroup() -> DispatchGroup {
            if let group { return group }
            let created = DispatchGroup(); group = created; return created
        }
        for delegate in delegates {
            guard shouldContinue() else { break }
            if (delegate as? BoundedMediaSourceDelegate)?.managesFrameBackpressure == true {
                delegate.mediaSource(source, didOutput: frame, completion: { _ in })
            } else {
                let group = waitingGroup()
                group.enter()
                let acknowledge = FrameProcessingCancellation { group.leave() }
                delegate.mediaSource(source, didOutput: frame) { _ in acknowledge.cancel() }
            }
        }
        let consumers = output.consumers
        if !consumers.isEmpty {
            let group = waitingGroup()
            group.enter()
            let acknowledge = FrameProcessingCancellation { group.leave() }
            output.transmit(frame, consumers: consumers, shouldContinue: shouldContinue) { _ in acknowledge.cancel() }
        }
        if let group {
            let transfer = CompletionTransfer(completion)
            group.notify(queue: .global(qos: .userInitiated)) { transfer.value() }
        } else { completion() }
    }
    private struct CompletionTransfer: @unchecked Sendable {
        let value: () -> Void
        init(_ value: @escaping () -> Void) { self.value = value }
    }
}
