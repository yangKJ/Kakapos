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
        let group = DispatchGroup()
        for delegate in delegates {
            guard shouldContinue() else { break }
            if (delegate as? BoundedMediaSourceDelegate)?.managesFrameBackpressure == true {
                delegate.mediaSource(source, didOutput: frame, completion: { _ in })
            } else {
                group.enter()
                let acknowledge = FrameProcessingCancellation { group.leave() }
                delegate.mediaSource(source, didOutput: frame) { _ in acknowledge.cancel() }
            }
        }
        group.enter()
        let acknowledge = FrameProcessingCancellation { group.leave() }
        output.transmit(frame, shouldContinue: shouldContinue) { _ in acknowledge.cancel() }
        let transfer = CompletionTransfer(completion)
        group.notify(queue: .global(qos: .userInitiated)) { transfer.value() }
    }
    private struct CompletionTransfer: @unchecked Sendable {
        let value: () -> Void
        init(_ value: @escaping () -> Void) { self.value = value }
    }
}
