// 作者：Condy
import Foundation
import KakaposMediaCore

/// 预览只保留最新画面，其 UI 确认和错误不占用录制的交付预算。
final class RecordingPreviewBranch: MediaSink {
    let preview: PreviewSink
    var errorHandler: ((Error) -> Void)?
    init(preview: PreviewSink) { self.preview = preview }
    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isAudioMediaFrame(frame) {
            preview.consume(frame) { [weak self] result in
                if case .failure(let error) = result { self?.errorHandler?(error) }
            }
        }
        completion(.success(()))
    }
    func pause() { preview.pause() }
    func resume() { preview.resume() }
    func cancel() { preview.cancel() }
    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        preview.finish { [weak self] result in
            if case .failure(let error) = result { self?.errorHandler?(error) }
        }
        completion(.success(()))
    }
}
