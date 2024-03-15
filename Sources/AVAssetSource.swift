//
//  AVAssetSource.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/10.
//

import Foundation
import AVFoundation

public class AVAssetSource: AVSourciable {
    public typealias Element = AVAsset
    public let element: AVAsset
    public var duration: CMTime = .zero
    public var isLoaded: Bool = false
    
    public required init(element: AVAsset) {
        self.element = element
    }
    
    public convenience init(videoURL: URL) {
        let urlAsset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.init(element: urlAsset)
    }
    
    public func load(completion: @escaping (Result<AVAsset, Exporter.Error>) -> Void) {
        self.element.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { [weak self] in
            guard let `self` = self else {
                return
            }
            defer { self.isLoaded = true }
            var error: NSError?
            let tracksStatus = self.element.statusOfValue(forKey: "tracks", error: &error)
            if tracksStatus != .loaded {
                completion(.failure(Exporter.Error.toError(error)))
                return
            }
            
            let durationStatus = self.element.statusOfValue(forKey: "duration", error: &error)
            if durationStatus != .loaded {
                completion(.failure(Exporter.Error.toError(error)))
                return
            }
            
            if let videoTrack = self.element.tracks(withMediaType: .video).first {
                // Make sure source's duration not beyond video track's duration
                self.duration = videoTrack.timeRange.duration
            } else {
                self.duration = self.element.duration
            }
            completion(.success(self.element))
        }
    }
    
    public func tracks(for type: AVMediaType) -> [AVAssetTrack] {
        var tracks: [AVAssetTrack] = []
        let group = DispatchGroup()
        group.enter()
        self.element.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: { [weak self] in
            guard let weakSelf = self else {
                group.leave()
                return
            }
            var error: NSError? = nil
            let status = weakSelf.element.statusOfValue(forKey: "tracks", error: &error)
            if status == .loaded {
                tracks = weakSelf.element.tracks(withMediaType: type)
            }
            group.leave()
        })
        group.wait()
        return tracks
    }
}
