//
//  InstructionTreeTraversal.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import KakaposMediaCore
import AVFoundation

enum InstructionTreeTraversal {
    static func splitReaderWriterInstructions(
        from instructions: [CompositionInstruction]
    ) -> (compositionInstructions: [CompositionInstruction], videoProcessors: [FrameProcessor]) {
        var compositionInstructions: [CompositionInstruction] = []
        var videoProcessors: [FrameProcessor] = []

        for instruction in instructions {
            let result = splitReaderWriterInstruction(instruction)
            if let compositionInstruction = result.compositionInstruction {
                compositionInstructions.append(compositionInstruction)
            }
            videoProcessors.append(contentsOf: result.videoProcessors)
        }

        return (compositionInstructions, videoProcessors)
    }

    static func firstRotationAngle(in instructions: [CompositionInstruction]) -> RotationAngle? {
        for instruction in instructions {
            if let rotationAngle = firstRotationAngle(in: instruction) {
                return rotationAngle
            }
        }
        return nil
    }

    private static func splitReaderWriterInstruction(
        _ instruction: CompositionInstruction
    ) -> (compositionInstruction: CompositionInstruction?, videoProcessors: [FrameProcessor]) {
        if let processorInstruction = instruction as? FrameProcessorProvidingInstruction,
           let processor = processorInstruction.kakaposFrameProcessor {
            return (nil, [processor])
        }

        guard let compositeInstruction = instruction as? CompositeInstruction else {
            return (instruction, [])
        }

        var compositionInstructions: [CompositionInstruction] = []
        var videoProcessors: [FrameProcessor] = []

        for child in compositeInstruction.instructions {
            let result = splitReaderWriterInstruction(child)
            if let compositionInstruction = result.compositionInstruction {
                compositionInstructions.append(compositionInstruction)
            }
            videoProcessors.append(contentsOf: result.videoProcessors)
        }

        if compositionInstructions.isEmpty {
            return (nil, videoProcessors)
        }

        return (
            CompositeInstruction(instructions: compositionInstructions),
            videoProcessors
        )
    }

    private static func firstRotationAngle(in instruction: CompositionInstruction) -> RotationAngle? {
        if let rotateInstruction = instruction as? RotateInstruction {
            return rotateInstruction.rotationAngle
        }

        guard let compositeInstruction = instruction as? CompositeInstruction else {
            return nil
        }

        for child in compositeInstruction.instructions {
            if let rotationAngle = firstRotationAngle(in: child) {
                return rotationAngle
            }
        }

        return nil
    }
}
