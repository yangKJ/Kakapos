//
//  HarbethFrameProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

#if canImport(Harbeth)
import Harbeth

public struct HarbethFrameProcessor: FrameProcessor {
    public var filters: [C7FilterProtocol]

    public init(filters: [C7FilterProtocol]) {
        self.filters = filters
    }

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        guard let pixelBuffer = frame.pixelBuffer else {
            completion(.success(frame))
            return
        }
        let output = HarbethIO(element: pixelBuffer, filters: filters)
        output.transmitOutput(success: { processedBuffer in
            var processedFrame = MediaFrame(pixelBuffer: processedBuffer, metadata: frame.metadata)
            if let sampleBuffer = frame.sampleBuffer {
                processedFrame.sampleBuffer = SampleBufferUtilities.replacingImageBuffer(of: sampleBuffer, with: processedBuffer)
            }
            completion(.success(processedFrame))
        }, failed: { error in
            completion(.failure(error))
        })
    }
}
#endif
