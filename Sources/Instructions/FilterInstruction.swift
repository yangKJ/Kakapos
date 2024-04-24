//
//  FilterInstruction.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/18.
//

import Foundation
import AVFoundation
import CoreVideo

public final class FilterInstruction: CompositionInstruction {
    
    /// Get the current pixel buffer in real time and give it to the outside world for processing.
    /// - buffer: Current pixel buffer.
    /// - time: Current frame, Start with the minimum time of `ExportSessionTimeRange`.
    /// - block: Asynchronous processing pixel buffer.
    public typealias BufferCallback = (_ buffer: CVPixelBuffer, _ time: Int64, _ block: @escaping BufferBlock) -> Void
    
    private let callback: BufferCallback
    
    public convenience init(filtering: @escaping (CVPixelBuffer, @escaping BufferBlock) -> Void) {
        let callback = { (buffer, _: Int64, block) -> Void in
            filtering(buffer, block)
        }
        self.init(callback: callback)
    }
    
    public init(callback: @escaping BufferCallback) {
        self.callback = callback
        super.init()
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
