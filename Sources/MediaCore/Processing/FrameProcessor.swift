//
//  FrameProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public protocol FrameProcessor {
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void)
}

public protocol FrameProcessingOperation: AnyObject, Sendable {
    func cancel()
}

public protocol CancellableFrameProcessor: FrameProcessor {
    @discardableResult
    func processCancellable(
        _ frame: MediaFrame,
        completion: @escaping (Result<MediaFrame, Error>) -> Void
    ) -> FrameProcessingOperation
}

public struct FrameProcessorCapabilities: Equatable, Sendable {
    public let acceptedPixelFormats: Set<FramePixelFormat>
    public let supportedDynamicRanges: Set<FrameDynamicRange>
    /// 描述处理结果是否保留输入色彩信息；这是供编排与诊断使用的事实字段，不参与输入准入。
    public let preservesColorInformation: Bool

    public init(
        acceptedPixelFormats: Set<FramePixelFormat> = [],
        supportedDynamicRanges: Set<FrameDynamicRange> = [],
        preservesColorInformation: Bool = true
    ) {
        self.acceptedPixelFormats = acceptedPixelFormats
        self.supportedDynamicRanges = supportedDynamicRanges
        self.preservesColorInformation = preservesColorInformation
    }

    public func accepts(_ format: FrameFormat) -> Bool {
        (acceptedPixelFormats.isEmpty || acceptedPixelFormats.contains(format.pixelFormat))
            && (supportedDynamicRanges.isEmpty || supportedDynamicRanges.contains(format.dynamicRange))
    }
}

public protocol FrameProcessorCapabilityProviding {
    var capabilities: FrameProcessorCapabilities { get }
}

public enum FrameProcessorCapabilityError: Error, Equatable {
    case unsupportedFormat(FrameFormat)
}

public final class FrameProcessingCancellation: FrameProcessingOperation, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    public init(_ cancellation: @escaping () -> Void = {}) {
        self.cancellation = cancellation
    }

    public func cancel() {
        let action: (() -> Void)?
        lock.lock()
        action = cancellation
        cancellation = nil
        lock.unlock()
        action?()
    }
}

@discardableResult
public func processFrame(
    using processor: FrameProcessor,
    frame: MediaFrame,
    completion: @escaping (Result<MediaFrame, Error>) -> Void
) -> FrameProcessingOperation? {
    if let provider = processor as? FrameProcessorCapabilityProviding,
       let format = frame.metadata.format,
       !provider.capabilities.accepts(format) {
        completion(.failure(FrameProcessorCapabilityError.unsupportedFormat(format)))
        return nil
    }
    if let processor = processor as? CancellableFrameProcessor {
        return processor.processCancellable(frame, completion: completion)
    }
    processor.process(frame, completion: completion)
    return nil
}

public struct PassthroughFrameProcessor: FrameProcessor {
    public init() {}

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        completion(.success(frame))
    }
}

public struct ClosureFrameProcessor: FrameProcessor {
    public typealias ProcessingBlock = (MediaFrame, @escaping (Result<MediaFrame, Error>) -> Void) -> Void

    private let block: ProcessingBlock

    public init(_ block: @escaping ProcessingBlock) {
        self.block = block
    }

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        block(frame, completion)
    }
}
