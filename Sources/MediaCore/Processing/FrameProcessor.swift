//
//  FrameProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public protocol FrameProcessor {
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void)
}

public struct PassthroughFrameProcessor: FrameProcessor {
    public init() {}

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        completion(.success(frame))
    }
}

public struct ClosureFrameProcessor: FrameProcessor {
    public typealias ProcessingBlock = (MediaFrame, @escaping (Result<MediaFrame, Error>) -> Void) -> Void

    private let block: ProcessingBlock

    public init(_ block: @escaping ProcessingBlock) {
        self.block = block
    }

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        block(frame, completion)
    }
}
