//
//  InstructionProtocol.swift
//  KakaposExamples
//
//  Created by Condy on 2024/4/12.
//

import Foundation
import AVFoundation
import CoreVideo

public protocol InstructionProtocol {
    
    func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest)
}

public typealias CompositionInstruction = Instruction & InstructionProtocol

/// 异步执行的闭包必须加`@escaping`
public typealias BufferBlock = (CVPixelBuffer) -> Void
