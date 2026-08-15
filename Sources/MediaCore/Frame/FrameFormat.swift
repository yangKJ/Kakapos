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

    public static let sdrBGRA8 = FrameFormat(
        pixelFormat: .bgra8,
        colorInfo: FrameColorInfo(
            primaries: .bt709,
            transferFunction: .sdr,
            yCbCrMatrix: .bt709
        ),
        dynamicRange: .standard
    )
}
