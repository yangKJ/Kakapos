//
//  FilterInstruction.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/18.
//

import Foundation
import AVFoundation
import CoreVideo

public final class FilterInstruction: CompositionInstruction, @unchecked Sendable {
    
    /// Get the current pixel buffer in real time and give it to the outside world for processing.
    /// - buffer: Current pixel buffer.
    /// - time: Current frame, Start with the minimum time of `ExportSessionTimeRange`.
    /// - block: Asynchronous processing pixel buffer.
    public typealias BufferCallback = (_ buffer: CVPixelBuffer, _ time: Int64, _ block: @escaping BufferBlock) -> Void
    
    private let callback: BufferCallback
    private let processor: FrameProcessor?
    
    public convenience init(filtering: @escaping (CVPixelBuffer, @escaping BufferBlock) -> Void) {
        let callback = { (buffer, _: Int64, block) -> Void in
            filtering(buffer, block)
        }
        self.init(callback: callback)
    }
    
    public init(callback: @escaping BufferCallback, processor: FrameProcessor? = nil) {
        self.callback = callback
        self.processor = processor
        super.init()
    }

    public convenience init(processor: FrameProcessor) {
        self.init(callback: { buffer, time, block in
            let metadata = FrameMetadata(
                presentationTime: CMTime(value: time, timescale: 1),
                sourceTime: CMTime(value: time, timescale: 1)
            )
            processor.process(PixelBufferFrame(pixelBuffer: buffer, metadata: metadata)) { result in
                switch result {
                case .success(let frame):
                    block(extractPixelBuffer(frame) ?? buffer)
                case .failure:
                    block(buffer)
                }
            }
        }, processor: processor)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        let compositionTime = request.compositionTime
        let time = compositionTime.value/Int64(compositionTime.timescale) - Int64(minTime)
        self.callback(buffer, time, block)
    }
}

extension FilterInstruction: FrameProcessorProvidingInstruction {
    var kakaposFrameProcessor: FrameProcessor? {
        processor
    }
}
