//
//  MediaSink.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import VideoToolbox
import CoreGraphics

public protocol MediaSink: AnyObject {
    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void)
    func finish(completion: @escaping (Result<Void, Error>) -> Void)
}

public extension MediaSink {
    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

public final class PixelBufferSink: MediaSink {
    public typealias Handler = (MediaFrame) -> Void
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        handler(frame)
        completion(.success(()))
    }
}

public final class PreviewSink: MediaSink {
    public typealias Handler = (CGImage, FrameMetadata) -> Void

    private let handler: Handler
    private let callbackQueue: DispatchQueue

    public init(
        callbackQueue: DispatchQueue = .main,
        handler: @escaping Handler
    ) {
        self.callbackQueue = callbackQueue
        self.handler = handler
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let pixelBuffer = frame.pixelBuffer else {
            completion(.failure(VideoX.Error.newRenderedPixelBufferForRequestFailure))
            return
        }
        var previewImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &previewImage)
        guard status == noErr, let previewImage else {
            completion(.failure(VideoX.Error.newRenderedPixelBufferForRequestFailure))
            return
        }
        callbackQueue.async {
            self.handler(previewImage, frame.metadata)
        }
        completion(.success(()))
    }
}
