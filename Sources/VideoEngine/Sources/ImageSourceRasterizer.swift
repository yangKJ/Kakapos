// 作者：Condy
import Foundation
import AVFoundation
import CoreGraphics

/// 仅在静帧源的生产队列使用；缓存模板不交给可变的外部处理器。
final class ImageSourceRasterizer {
    private struct Key: Hashable {
        let image: ObjectIdentifier
        let width: Int
        let height: Int
    }
    private struct Entry {
        let image: CGImage
        let buffer: CVPixelBuffer
        let bytes: Int
        var access: UInt64
    }
    private var cache: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    private(set) var cachedBytes = 0
    private(set) var rasterizationCount = 0

    func makeBuffer(image: CGImage, size: CGSize?, budget: Int) throws -> CVPixelBuffer {
        let width = max(Int(size?.width ?? CGFloat(image.width)), 1)
        let height = max(Int(size?.height ?? CGFloat(image.height)), 1)
        let key = Key(image: ObjectIdentifier(image), width: width, height: height)
        let output = try outputBuffer(width: width, height: height)
        access &+= 1
        let template: CVPixelBuffer
        if var entry = cache[key] {
            entry.access = access
            cache[key] = entry
            template = entry.buffer
        } else {
            if width > budget / 4 / height {
                try draw(image, into: output)
                return output
            }
            var created: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &created) == kCVReturnSuccess,
                  let created else { throw VideoX.Error.newRenderedPixelBufferForRequestFailure }
            try draw(image, into: created)
            let bytes = CVPixelBufferGetBytesPerRow(created) * height
            while cachedBytes > max(0, budget - bytes), let oldest = cache.min(by: { $0.value.access < $1.value.access }) {
                cachedBytes -= oldest.value.bytes
                cache.removeValue(forKey: oldest.key)
            }
            if bytes <= budget {
                cache[key] = Entry(image: image, buffer: created, bytes: bytes, access: access)
                cachedBytes += bytes
            }
            template = created
        }
        CVPixelBufferLockBaseAddress(template, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(template, .readOnly)
        }
        guard let source = CVPixelBufferGetBaseAddress(template), let destination = CVPixelBufferGetBaseAddress(output) else {
            throw VideoX.Error.newRenderedPixelBufferForRequestFailure
        }
        for row in 0..<height {
            memcpy(destination.advanced(by: row * CVPixelBufferGetBytesPerRow(output)),
                source.advanced(by: row * CVPixelBufferGetBytesPerRow(template)), width * 4)
        }
        return output
    }

    private func outputBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            var created: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(nil, nil, [
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary, &created)
            guard status == kCVReturnSuccess else { throw VideoX.Error.newRenderedPixelBufferForRequestFailure }
            pool = created
            poolSize = size
        }
        var output: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
              let output else { throw VideoX.Error.newRenderedPixelBufferForRequestFailure }
        return output
    }

    private func draw(_ image: CGImage, into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let address = CVPixelBufferGetBaseAddress(buffer), let context = CGContext(data: address,
            width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw VideoX.Error.newRenderedPixelBufferForRequestFailure
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(bounds)
        context.draw(image, in: bounds)
        rasterizationCount += 1
    }
}
