//
//  VideoColorConversionProcessor.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import CoreImage
import CoreVideo
import KakaposMediaCore

/// 显式 HDR 输出 profile 的颜色转换；传递真实像素值及其格式。
final class VideoColorConversionProcessor: FrameProcessor, FrameProcessorCapabilityProviding {
    let policy: VideoExportColorPolicy
    let capabilities = FrameProcessorCapabilities(supportedDynamicRanges: [.standard, .hdr(.hlg), .hdr(.pq)])
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!,
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
    ])
    private var pool: CVPixelBufferPool?
    private var size = CGSize.zero
    private let lock = NSLock()

    init(policy: VideoExportColorPolicy) { self.policy = policy }

    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        guard let input = extractPixelBuffer(frame) else {
            completion(.failure(MediaCoreError.pixelBufferUnavailable))
            return
        }
        let format = FrameFormat(pixelBuffer: input)
        guard format.dynamicRange != .unknown else {
            completion(.failure(VideoExportProfileError.invalidHDROutput))
            return
        }
        if format.dynamicRange == policy.requestedDynamicRange,
            format.pixelFormat == .yuv420BiPlanar10BitVideoRange
        {
            completion(.success(frame))
            return
        }
        guard #available(iOS 14.1, tvOS 14.2, macOS 11, watchOS 7.1, *) else {
            completion(.failure(VideoExportProfileError.invalidHDROutput))
            return
        }
        let colorSpace = CGColorSpace(name: policy == .hdrHLG ? CGColorSpace.itur_2100_HLG : CGColorSpace.itur_2100_PQ)!
        let inputSize = CGSize(width: CVPixelBufferGetWidth(input), height: CVPixelBufferGetHeight(input))
        lock.lock()
        if pool == nil || size != inputSize {
            var created: CVPixelBufferPool?
            let attributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: Int(inputSize.width),
                kCVPixelBufferHeightKey as String: Int(inputSize.height),
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
            pool = created
            size = inputSize
        }
        let currentPool = pool
        lock.unlock()
        var output: CVPixelBuffer?
        guard let currentPool,
            CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                nil, currentPool, [kCVPixelBufferPoolAllocationThresholdKey: 4] as CFDictionary, &output)
                == kCVReturnSuccess,
            let output
        else {
            completion(.failure(VideoExportProfileError.invalidHDROutput))
            return
        }
        let image = CIImage(cvPixelBuffer: input, options: [.toneMapHDRtoSDR: false])
        context.render(image, to: output, bounds: CGRect(origin: .zero, size: inputSize), colorSpace: colorSpace)
        CVBufferSetAttachment(
            output, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(
            output, kCVImageBufferTransferFunctionKey,
            policy == .hdrHLG
                ? kCVImageBufferTransferFunction_ITU_R_2100_HLG : kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
            .shouldPropagate)
        CVBufferSetAttachment(
            output, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        var metadata = frame.metadata
        metadata.format = FrameFormat(pixelBuffer: output)
        completion(.success(PixelBufferFrame(pixelBuffer: output, metadata: metadata)))
    }
}
