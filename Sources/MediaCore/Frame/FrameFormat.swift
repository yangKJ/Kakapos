//
//  FrameFormat.swift
//  Kakapos
//
//  Created by Condy on 2026/8/15.
//

import CoreVideo
import Foundation

public enum FramePixelFormat: Equatable, Hashable, Sendable {
    case bgra8
    case argb8
    case yuv420BiPlanarVideoRange
    case yuv420BiPlanarFullRange
    case yuv420BiPlanar10BitVideoRange
    case yuv420BiPlanar10BitFullRange
    case other(fourCC: UInt32)
    case unknown

    public init(ostype: OSType?) {
        guard let ostype else {
            self = .unknown
            return
        }
        switch ostype {
        case kCVPixelFormatType_32BGRA:
            self = .bgra8
        case kCVPixelFormatType_32ARGB:
            self = .argb8
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            self = .yuv420BiPlanarVideoRange
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            self = .yuv420BiPlanarFullRange
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            self = .yuv420BiPlanar10BitVideoRange
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            self = .yuv420BiPlanar10BitFullRange
        default:
            self = .other(fourCC: ostype)
        }
    }
}

public enum FrameColorPrimaries: Equatable, Hashable, Sendable {
    case bt709
    case bt2020
    case p3D65
    case unknown(String?)
}

public enum FrameTransferFunction: Equatable, Hashable, Sendable {
    case sdr
    case hlg
    case pq
    case unknown(String?)
}

public enum FrameYCbCrMatrix: Equatable, Hashable, Sendable {
    case bt601
    case bt709
    case bt2020
    case identity
    case unknown(String?)
}

public struct FrameColorInfo: Equatable, Hashable, Sendable {
    public let primaries: FrameColorPrimaries
    public let transferFunction: FrameTransferFunction
    public let yCbCrMatrix: FrameYCbCrMatrix

    public init(
        primaries: FrameColorPrimaries,
        transferFunction: FrameTransferFunction,
        yCbCrMatrix: FrameYCbCrMatrix
    ) {
        self.primaries = primaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
    }
}

public enum FrameDynamicRange: Equatable, Hashable, Sendable {
    case standard
    case hdr(FrameTransferFunction)
    case unknown
}

public struct FrameFormat: Equatable, Hashable, Sendable {
    public let pixelFormat: FramePixelFormat
    public let colorInfo: FrameColorInfo
    public let dynamicRange: FrameDynamicRange

    public init(pixelFormat: FramePixelFormat, colorInfo: FrameColorInfo, dynamicRange: FrameDynamicRange) {
        self.pixelFormat = pixelFormat
        self.colorInfo = colorInfo
        self.dynamicRange = dynamicRange
    }

    /// 从解码后的像素缓冲区读取真实格式，而不是沿用压缩轨道或输出请求的假设。
    public init(pixelBuffer: CVPixelBuffer) {
        let pixelFormat = FramePixelFormat(ostype: CVPixelBufferGetPixelFormatType(pixelBuffer))
        let transfer = Self.transferFunction(from: pixelBuffer)
        let dynamicRange: FrameDynamicRange
        switch transfer {
        case .hlg, .pq:
            dynamicRange = .hdr(transfer)
        case .sdr:
            dynamicRange = .standard
        case let .unknown(value):
            if value == nil, pixelFormat != .yuv420BiPlanar10BitVideoRange,
               pixelFormat != .yuv420BiPlanar10BitFullRange {
                dynamicRange = .standard
            } else {
                dynamicRange = .unknown
            }
        }
        self.init(
            pixelFormat: pixelFormat,
            colorInfo: FrameColorInfo(
                primaries: Self.colorPrimaries(from: pixelBuffer),
                transferFunction: transfer,
                yCbCrMatrix: Self.yCbCrMatrix(from: pixelBuffer, pixelFormat: pixelFormat)
            ),
            dynamicRange: dynamicRange
        )
    }

    public static let sdrBGRA8 = FrameFormat(
        pixelFormat: .bgra8,
        colorInfo: FrameColorInfo(
            primaries: .bt709,
            transferFunction: .sdr,
            yCbCrMatrix: .identity
        ),
        dynamicRange: .standard
    )

    private static func colorPrimaries(from buffer: CVPixelBuffer) -> FrameColorPrimaries {
        let value = attachmentString(buffer, key: kCVImageBufferColorPrimariesKey)
        if value == kCVImageBufferColorPrimaries_ITU_R_2020 as String { return .bt2020 }
        if value == kCVImageBufferColorPrimaries_P3_D65 as String { return .p3D65 }
        if value == nil || value == kCVImageBufferColorPrimaries_ITU_R_709_2 as String { return .bt709 }
        return .unknown(value)
    }

    private static func transferFunction(from buffer: CVPixelBuffer) -> FrameTransferFunction {
        let value = attachmentString(buffer, key: kCVImageBufferTransferFunctionKey)
        guard let value else { return .unknown(nil) }
        if value == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { return .hlg }
        if value == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { return .pq }
        if value == kCVImageBufferTransferFunction_ITU_R_709_2 as String
            || value == kCVImageBufferTransferFunction_sRGB as String {
            return .sdr
        }
        return .unknown(value)
    }

    private static func yCbCrMatrix(
        from buffer: CVPixelBuffer,
        pixelFormat: FramePixelFormat
    ) -> FrameYCbCrMatrix {
        let value = attachmentString(buffer, key: kCVImageBufferYCbCrMatrixKey)
        if value == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String { return .bt601 }
        if value == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String { return .bt709 }
        if value == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String { return .bt2020 }
        if value == nil {
            return pixelFormat == .bgra8 || pixelFormat == .argb8 ? .identity : .bt709
        }
        return .unknown(value)
    }

    private static func attachmentString(_ buffer: CVPixelBuffer, key: CFString) -> String? {
        if #available(iOS 15, tvOS 15, watchOS 8, macOS 12, *) {
            return CVBufferCopyAttachment(buffer, key, nil) as? String
        }
        return CVBufferGetAttachment(buffer, key, nil)?.takeUnretainedValue() as? String
    }
}
