//
//  FilterInstruction.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/18.
//

import Foundation
import AVFoundation

public final class FilterInstruction: CompositionInstruction {
    
    /// Get the current pixel buffer in real time and give it to the outside world for processing.
    /// - buffer: Current pixel buffer.
    /// - time: Current frame, Start with the minimum time of `ExportSessionTimeRange`.
    /// - block: Asynchronous processing pixel buffer.
    public typealias BufferCallback = (_ buffer: ExporterBuffer, _ time: Int64, _ block: @escaping (ExporterBuffer) -> Void) -> Void
    
    public typealias PixelBufferCallback = (_ buffer: ExporterBuffer, _ block: @escaping (ExporterBuffer) -> Void) -> Void?
    
    let callback: BufferCallback
    
    public convenience init(filtering: @escaping PixelBufferCallback) {
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
    
    public override func handyPixelBuffer(_ buffer: ExporterBuffer, block: @escaping (ExporterBuffer) -> Void, compositionTime: CMTime) {
        let minTime = Exporter.Option.setupExportSessionMinTime(options: options)
        let time = compositionTime.value/Int64(compositionTime.timescale) - Int64(minTime)
        self.callback(buffer, time, block)
    }
}
