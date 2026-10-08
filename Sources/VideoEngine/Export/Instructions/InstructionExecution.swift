//
//  InstructionExecution.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import AVFoundation
import KakaposMediaCore

/// 有错误和取消语义的内部通道；旧 callback 指令通过适配继续工作。
func executeInstruction(
    _ instruction: CompositionInstruction,
    buffer: CVPixelBuffer,
    request: AVAsynchronousVideoCompositionRequest,
    completion: @escaping (Result<CVPixelBuffer, Error>) -> Void
) -> FrameProcessingOperation? {
    if let filter = instruction as? FilterInstruction, let processor = filter.kakaposFrameProcessor {
        let frame = PixelBufferFrame(
            pixelBuffer: buffer,
            metadata: FrameMetadata(
                presentationTime: request.compositionTime,
                sourceTime: request.compositionTime,
                format: FrameFormat(pixelBuffer: buffer)
            ))
        return processFrame(using: processor, frame: frame) { result in
            completion(
                result.flatMap { frame in
                    guard let output = extractPixelBuffer(frame) else {
                        return .failure(MediaCoreError.pixelBufferUnavailable)
                    }
                    return .success(output)
                })
        }
    }
    if let composite = instruction as? CompositeInstruction {
        let run = InstructionSequenceRun(completion: completion)
        run.process(composite.instructions, at: 0, buffer: buffer, request: request)
        return run
    }
    let lock = NSLock()
    var completed = false
    instruction.operationPixelBuffer(
        buffer,
        block: { output in
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            lock.unlock()
            completion(.success(output))
        }, for: request)
    return nil
}

private final class InstructionSequenceRun: FrameProcessingOperation, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var operation: FrameProcessingOperation?
    private let completion: (Result<CVPixelBuffer, Error>) -> Void

    init(completion: @escaping (Result<CVPixelBuffer, Error>) -> Void) { self.completion = completion }

    func cancel() {
        lock.lock()
        cancelled = true
        let operation = self.operation
        self.operation = nil
        lock.unlock()
        operation?.cancel()
    }

    func process(
        _ instructions: [CompositionInstruction], at index: Int, buffer: CVPixelBuffer,
        request: AVAsynchronousVideoCompositionRequest
    ) {
        lock.lock()
        let active = !cancelled
        lock.unlock()
        guard active else { return }
        guard index < instructions.count else {
            completion(.success(buffer))
            return
        }
        let operation = executeInstruction(instructions[index], buffer: buffer, request: request) { result in
            switch result {
            case .success(let output): self.process(instructions, at: index + 1, buffer: output, request: request)
            case .failure(let error): self.completion(.failure(error))
            }
        }
        lock.lock()
        if !cancelled { self.operation = operation }
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { operation?.cancel() }
    }
}
