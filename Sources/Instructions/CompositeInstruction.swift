//
//  CompositeInstruction.swift
//  Kakapos
//
//  Created by Condy on 2024/4/12.
//

import Foundation
import AVFoundation
import CoreVideo

/// Composite instructions are used to process multiple instructions sequentially.
public final class CompositeInstruction: Instruction, InstructionProtocol, @unchecked Sendable {
    
    let instructions: [CompositionInstruction]
    
    public init(instructions: [CompositionInstruction]) {
        self.instructions = instructions
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.instructions = []
        super.init(coder: aDecoder)
    }
    
    public override func setup() {
        super.setup()
        instructions.forEach { $0.setup() }
    }
    
    override func initCompositionTrack(_ track: AVCompositionTrack, provider: VideoX.Provider, options: [VideoX.Option: Any]) {
        super.initCompositionTrack(track, provider: provider, options: options)
        instructions.forEach { $0.initCompositionTrack(track, provider: provider, options: options) }
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        processNextInstruction(index: 0, buffer: buffer, request: request, callback: block)
    }
    
    private func processNextInstruction(index: Int, buffer: CVPixelBuffer, request: AVAsynchronousVideoCompositionRequest, callback: @escaping BufferBlock) {
        guard index < instructions.count else {
            callback(buffer)
            return
        }
        let instruction = instructions[index]
        instruction.operationPixelBuffer(buffer, block: { processedBuffer in
            self.processNextInstruction(index: index + 1, buffer: processedBuffer, request: request, callback: callback)
        }, for: request)
    }
}
