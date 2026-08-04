//
//  HarbethExampleFrameProcessor.swift
//  KakaposExamples
//
//  Created by Condy on 2026/8/4.
//

import CoreVideo
import Foundation
import Harbeth

private enum HarbethExampleFrameProcessorError: Error {
    case pixelBufferUnavailable
}

struct HarbethExampleFrameProcessor: FrameProcessor {
    let filters: [C7FilterProtocol]

    func process(
        _ frame: MediaFrame,
        completion: @escaping (Result<MediaFrame, Error>) -> Void
    ) {
        guard let pixelBuffer = extractPixelBuffer(frame) else {
            completion(.failure(HarbethExampleFrameProcessorError.pixelBufferUnavailable))
            return
        }
        let output = HarbethIO(element: pixelBuffer, filters: filters)
        output.transmitOutput(success: { processedBuffer in
            completion(.success(PixelBufferFrame(
                pixelBuffer: processedBuffer,
                metadata: frame.metadata
            )))
        }, failed: { error in
            completion(.failure(error))
        })
    }
}

extension KakaposWrapper where Base: CVPixelBuffer {
    func filtering(with filters: [C7FilterProtocol], callback: @escaping BufferBlock) {
        let output = HarbethIO(element: base, filters: filters)
        output.transmitOutput(success: callback, failed: { _ in
            callback(base)
        })
    }
}
