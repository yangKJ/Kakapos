//
//  TimelineEffectProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import AVFoundation
import CoreImage
import CoreVideo
import KakaposMediaCore

public enum TimelineEffectError: Error {
    case invalidIntensity
    case pixelBufferUnavailable
    case incompatibleOutput
    case hdrProcessorNotAdmitted
    case bufferAllocationFailed(CVReturn)
}

/// 整帧效果的时间段与线性光强度执行器；编辑数据在创建时冻结。
final class TimelineEffectProcessor: CancellableFrameProcessor, FrameProcessorCapabilityProviding {
    var capabilities: FrameProcessorCapabilities {
        (processor as? FrameProcessorCapabilityProviding)?.capabilities ?? FrameProcessorCapabilities()
    }
    private let segment: TimelineProcessorSegment
    private let processor: FrameProcessor
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!,
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
    ])
    private let poolLock = NSLock()
    private var pool: CVPixelBufferPool?
    private var poolKey: [Int] = []

    init(segment: TimelineProcessorSegment, processor: FrameProcessor) {
        self.segment = segment
        self.processor = processor
    }

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        _ = processCancellable(frame, completion: completion)
    }

    func processCancellable(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void)
        -> FrameProcessingOperation
    {
        let time = frame.metadata.presentationTime
        guard time.isNumeric, CMTimeRangeContainsTime(segment.destinationTimeRange, time: time) else {
            completion(.success(frame))
            return FrameProcessingCancellation()
        }
        let value = segment.intensity(at: time)
        guard value.isFinite else {
            completion(.failure(TimelineEffectError.invalidIntensity))
            return FrameProcessingCancellation()
        }
        let intensity = min(1, max(0, value))
        guard intensity > 0 else {
            completion(.success(frame))
            return FrameProcessingCancellation()
        }
        let input = extractPixelBuffer(frame)
        let format = input.map { FrameFormat(pixelBuffer: $0) }
        if case .hdr = format?.dynamicRange {
            guard let capabilities = (processor as? FrameProcessorCapabilityProviding)?.capabilities,
                let format, capabilities.supportedDynamicRanges.contains(format.dynamicRange),
                capabilities.preservesColorInformation
            else {
                completion(.failure(TimelineEffectError.hdrProcessorNotAdmitted))
                return FrameProcessingCancellation()
            }
        }
        let operation = processFrame(using: processor, frame: frame) { result in
            completion(
                result.flatMap { processed in
                    do {
                        if let input, let output = extractPixelBuffer(processed) {
                            guard CVPixelBufferGetWidth(input) == CVPixelBufferGetWidth(output),
                                CVPixelBufferGetHeight(input) == CVPixelBufferGetHeight(output)
                            else {
                                throw TimelineEffectError.incompatibleOutput
                            }
                            if case .hdr = format?.dynamicRange,
                                FrameFormat(pixelBuffer: output) != format
                            {
                                throw TimelineEffectError.incompatibleOutput
                            }
                        } else if intensity < 1 || format?.dynamicRange != nil {
                            throw TimelineEffectError.pixelBufferUnavailable
                        }
                        guard intensity < 1 else { return .success(processed) }
                        guard let input, let output = extractPixelBuffer(processed) else {
                            throw TimelineEffectError.pixelBufferUnavailable
                        }
                        return .success(
                            try self.blend(input: input, output: output, intensity: intensity, metadata: frame.metadata)
                        )
                    } catch { return .failure(error) }
                })
        }
        return operation ?? FrameProcessingCancellation()
    }

    private func blend(input: CVPixelBuffer, output: CVPixelBuffer, intensity: Float, metadata: FrameMetadata) throws
        -> MediaFrame
    {
        let format = FrameFormat(pixelBuffer: input)
        let destinationSpace: CGColorSpace
        switch format.dynamicRange {
        case .standard:
            destinationSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        case .hdr(.hlg):
            if #available(iOS 14, tvOS 14, macOS 11, watchOS 7, *) {
                destinationSpace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
            } else {
                throw TimelineEffectError.incompatibleOutput
            }
        case .hdr(.pq):
            if #available(iOS 14, tvOS 14, macOS 11, watchOS 7, *) {
                destinationSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
            } else {
                throw TimelineEffectError.incompatibleOutput
            }
        default: throw TimelineEffectError.incompatibleOutput
        }
        let key = [
            CVPixelBufferGetWidth(input), CVPixelBufferGetHeight(input), Int(CVPixelBufferGetPixelFormatType(input)),
        ]
        poolLock.lock()
        if poolKey != key {
            var created: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                nil, nil,
                [
                    kCVPixelBufferWidthKey: key[0],
                    kCVPixelBufferHeightKey: key[1],
                    kCVPixelBufferPixelFormatTypeKey: key[2],
                    kCVPixelBufferIOSurfacePropertiesKey: [:],
                    kCVPixelBufferMetalCompatibilityKey: true,
                ] as CFDictionary, &created)
            guard status == kCVReturnSuccess else {
                poolLock.unlock()
                throw TimelineEffectError.bufferAllocationFailed(status)
            }
            pool = created
            poolKey = key
        }
        let currentPool = pool!
        poolLock.unlock()
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            nil, currentPool,
            [
                kCVPixelBufferPoolAllocationThresholdKey: 4
            ] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw TimelineEffectError.bufferAllocationFailed(status) }
        let image = CIImage(cvPixelBuffer: input).applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: CIImage(cvPixelBuffer: output),
                kCIInputTimeKey: intensity,
            ])
        context.render(image, to: buffer, bounds: image.extent, colorSpace: destinationSpace)
        // 只复制色彩合同，不继承经过效果处理后可能已经失真的 HDR 内容统计。
        for key in [kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey, kCVImageBufferYCbCrMatrixKey] {
            if let value = CVBufferGetAttachment(input, key, nil)?.takeUnretainedValue() {
                CVBufferSetAttachment(buffer, key, value, .shouldPropagate)
            }
        }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, destinationSpace, .shouldPropagate)
        var metadata = metadata
        metadata.format = FrameFormat(pixelBuffer: buffer)
        return PixelBufferFrame(pixelBuffer: buffer, metadata: metadata)
    }
}
