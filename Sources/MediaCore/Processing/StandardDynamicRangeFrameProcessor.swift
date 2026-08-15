//
//  StandardDynamicRangeFrameProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// 将 HLG/PQ 像素值显式映射到标准动态范围，再交给只支持 SDR 的处理器。
public final class StandardDynamicRangeFrameProcessor: FrameProcessor, FrameProcessorCapabilityProviding, @unchecked Sendable {
    public enum ProcessingError: Error, Equatable {
        case pixelBufferUnavailable
        case outputBufferCreationFailed(CVReturn)
        case hdrToneMappingUnavailable
        case dynamicRangeUndetermined
    }

    /// 空输入集合表示接纳所有可提取的像素缓冲区；处理器会根据实际 CV 附件决定直通、映射或拒绝。
    public let capabilities = FrameProcessorCapabilities(preservesColorInformation: false)

    private let context: CIContext
    private let outputColorSpace: CGColorSpace
    private let poolLock = NSLock()
    private var outputPool: CVPixelBufferPool?
    private var outputSize = CGSize.zero

    public init() {
        context = CIContext(options: [.cacheIntermediates: false])
        outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    }

    public func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        guard let source = extractPixelBuffer(frame) else {
            completion(.failure(ProcessingError.pixelBufferUnavailable))
            return
        }
        let sourceFormat = FrameFormat(pixelBuffer: source)
        switch sourceFormat.dynamicRange {
        case .standard:
            var metadata = frame.metadata
            metadata.format = sourceFormat
            completion(.success(PixelBufferFrame(pixelBuffer: source, metadata: metadata)))
            return
        case .unknown:
            completion(.failure(ProcessingError.dynamicRangeUndetermined))
            return
        case .hdr:
            break
        }

        do {
            let output = try makeOutputBuffer(matching: source)
            let image: CIImage
            if #available(iOS 14.1, tvOS 14.2, watchOS 7.1, macOS 11, *) {
                image = CIImage(cvPixelBuffer: source, options: [.toneMapHDRtoSDR: true])
            } else {
                throw ProcessingError.hdrToneMappingUnavailable
            }
            context.render(
                image,
                to: output,
                bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source)),
                colorSpace: outputColorSpace
            )
            publishStandardDynamicRangeAttachments(on: output)
            var metadata = frame.metadata
            metadata.format = FrameFormat(pixelBuffer: output)
            completion(.success(PixelBufferFrame(pixelBuffer: output, metadata: metadata)))
        } catch {
            completion(.failure(error))
        }
    }

    private func makeOutputBuffer(matching source: CVPixelBuffer) throws -> CVPixelBuffer {
        let size = CGSize(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source))
        let pool: CVPixelBufferPool?
        poolLock.lock()
        do {
            if outputPool == nil || outputSize != size {
                outputPool = try makeOutputPool(size: size)
                outputSize = size
            }
            pool = outputPool
            poolLock.unlock()
        } catch {
            poolLock.unlock()
            throw error
        }
        guard let pool else {
            throw ProcessingError.outputBufferCreationFailed(kCVReturnInvalidPoolAttributes)
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw ProcessingError.outputBufferCreationFailed(status)
        }
        return buffer
    }

    private func makeOutputPool(size: CGSize) throws -> CVPixelBufferPool {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
            attributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw ProcessingError.outputBufferCreationFailed(status)
        }
        return pool
    }

    private func publishStandardDynamicRangeAttachments(on buffer: CVPixelBuffer) {
        CVBufferSetAttachment(
            buffer,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            buffer,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_sRGB,
            .shouldPropagate
        )
        CVBufferRemoveAttachment(buffer, kCVImageBufferYCbCrMatrixKey)
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, outputColorSpace, .shouldPropagate)
    }
}
