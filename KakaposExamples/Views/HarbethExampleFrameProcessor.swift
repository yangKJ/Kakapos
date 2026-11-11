//
//  HarbethExampleFrameProcessor.swift
//  KakaposExamples
//
//  Created by Condy on 2026/8/4.
//

import CoreVideo
import Foundation
import Harbeth
import Kakapos

private enum HarbethExampleFrameProcessorError: LocalizedError {
    case pixelBufferUnavailable
    case hdrExecutionNotAdmitted

    var errorDescription: String? {
        switch self {
        case .pixelBufferUnavailable: return "处理帧缺少像素缓冲区。"
        case .hdrExecutionNotAdmitted: return "滤镜执行图不能满足HDR精度或动态范围合同。"
        }
    }
}

struct HarbethExampleFrameProcessor: FrameProcessor, FrameProcessorCapabilityProviding {
    var capabilities: FrameProcessorCapabilities {
        FrameProcessorCapabilities(supportedDynamicRanges: [.standard, .hdr(.hlg), .hdr(.pq)])
    }
    let filters: [C7FilterProtocol]

    func process(
        _ frame: MediaFrame,
        completion: @escaping (Result<MediaFrame, Error>) -> Void
    ) {
        guard let pixelBuffer = extractPixelBuffer(frame) else {
            completion(.failure(HarbethExampleFrameProcessorError.pixelBufferUnavailable))
            return
        }
        if case .hdr(let transfer) = FrameFormat(pixelBuffer: pixelBuffer).dynamicRange {
            do {
                let source = ImageNode.pixelBuffer(pixelBuffer)
                let node = source.applying(filters: filters)
                let capability = try node.makeFrameProcessingCapability(for: .extendedRangeDynamicFrame, profile: .exportQuality)
                guard capability.isSupported else { throw HarbethExampleFrameProcessorError.hdrExecutionNotAdmitted }
                let rendered = try node.makeFrame(profile: .exportQuality)
                let pixels = try rendered.makePixelBuffer(pixelFormatType: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                    outputColorSpace: transfer == .hlg ? .hdrHLG : .hdrPQ, allowsAlphaDiscard: true)
                var metadata = frame.metadata
                metadata.format = FrameFormat(pixelBuffer: pixels)
                completion(.success(PixelBufferFrame(pixelBuffer: pixels, metadata: metadata)))
            } catch {
                completion(.failure(error))
            }
            return
        }
        let delivery = ExampleFrameDelivery(frame: frame, completion: completion)
        let output = HarbethIO(element: pixelBuffer, filters: filters)
        output.transmitOutput(success: { processedBuffer in
            delivery.completion(.success(PixelBufferFrame(pixelBuffer: processedBuffer, metadata: delivery.frame.metadata)))
        }, failed: { error in
            delivery.completion(.failure(error))
        })
    }
}

extension KakaposWrapper where Base: CVPixelBuffer {
    func filtering(with filters: [C7FilterProtocol], callback: @escaping BufferBlock) {
        let delivery = ExampleBufferDelivery(buffer: base, callback: callback)
        let output = HarbethIO(element: base, filters: filters)
        output.transmitOutput(success: { delivery.callback($0) }, failed: { _ in
            delivery.callback(delivery.buffer)
        })
    }
}

/// 源缓冲与回调一起持有，异步渲染期间不借用调用方的可变状态。
private struct ExampleFrameDelivery: @unchecked Sendable {
    let frame: MediaFrame
    let completion: (Result<MediaFrame, Error>) -> Void
}

private struct ExampleBufferDelivery: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let callback: BufferBlock
}
