//
//  ImageSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct StillImageFrame {
    public var image: CGImage
    public var duration: CMTime
    public var transform: CGAffineTransform
    public var userInfo: [String: Any]

    public init(
        image: CGImage,
        duration: CMTime = CMTime(value: 1, timescale: 30),
        transform: CGAffineTransform = .identity,
        userInfo: [String: Any] = [:]
    ) {
        self.image = image
        self.duration = duration
        self.transform = transform
        self.userInfo = userInfo
    }
}

public final class ImageSource: MediaSource, MediaFrameSourceNode {
    public enum MetadataKey {
        public static let imageIndex = "kakapos.image-source.index"
        public static let imageCount = "kakapos.image-source.count"
        public static let isLooping = "kakapos.image-source.looping"
    }

    public weak var delegate: MediaSourceDelegate?
    public var frames: [StillImageFrame]
    public var renderSize: CGSize?
    public var isLooping: Bool
    public var callbackQueue: DispatchQueue

    private let queue = DispatchQueue(label: "com.condy.kakapos.image-source")
    private let outputNode = MediaOutputNode()
    private let pauseCondition = NSCondition()
    private var shouldStop = false
    private var isPaused = false
    private var isCancelled = false
    private var currentIndex = 0
    private var currentPresentationTime: CMTime = .zero

    public init(
        frames: [StillImageFrame],
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main
    ) {
        self.frames = frames
        self.renderSize = renderSize
        self.isLooping = isLooping
        self.callbackQueue = callbackQueue
    }

    public convenience init(
        image: CGImage,
        duration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        callbackQueue: DispatchQueue = .main
    ) {
        self.init(
            frames: [StillImageFrame(image: image, duration: duration)],
            renderSize: renderSize,
            isLooping: false,
            callbackQueue: callbackQueue
        )
    }

    #if canImport(UIKit)
    public convenience init(
        images: [UIImage],
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main
    ) {
        let frames = images.compactMap { image -> StillImageFrame? in
            guard let cgImage = image.cgImage else { return nil }
            return StillImageFrame(image: cgImage, duration: frameDuration)
        }
        self.init(frames: frames, renderSize: renderSize, isLooping: isLooping, callbackQueue: callbackQueue)
    }
    #elseif canImport(AppKit)
    public convenience init(
        images: [NSImage],
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        renderSize: CGSize? = nil,
        isLooping: Bool = false,
        callbackQueue: DispatchQueue = .main
    ) {
        let frames = images.compactMap { image -> StillImageFrame? in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return StillImageFrame(image: cgImage, duration: frameDuration)
        }
        self.init(frames: frames, renderSize: renderSize, isLooping: isLooping, callbackQueue: callbackQueue)
    }
    #endif

    public func start() {
        queue.async {
            guard !self.frames.isEmpty else {
                self.callbackQueue.async {
                    self.delegate?.mediaSourceDidFinish(self)
                }
                return
            }
            self.shouldStop = false
            self.isCancelled = false
            self.consumeFrames()
        }
    }

    public func pause() {
        pauseCondition.lock()
        isPaused = true
        pauseCondition.unlock()
    }

    public func resume() {
        pauseCondition.lock()
        isPaused = false
        pauseCondition.broadcast()
        pauseCondition.unlock()
    }

    public func stop() {
        queue.async {
            self.shouldStop = true
            self.resume()
        }
    }

    public func cancel() {
        queue.async {
            self.isCancelled = true
            self.shouldStop = true
            self.resume()
            self.callbackQueue.async {
                self.delegate?.mediaSourceDidFinish(self)
            }
        }
    }

    private func consumeFrames() {
        repeat {
            while currentIndex < frames.count && !shouldStop && !isCancelled {
                waitIfNeeded()
                if shouldStop || isCancelled {
                    break
                }

                let item = frames[currentIndex]
                do {
                    let pixelBuffer = try Self.makePixelBuffer(from: item.image, renderSize: renderSize)
                    let metadata = FrameMetadata(
                        presentationTime: currentPresentationTime,
                        duration: item.duration,
                        sourceTime: currentPresentationTime,
                        trackTransform: item.transform,
                        frameIndex: Int64(currentIndex),
                        userInfo: item.userInfo.merging([
                            MetadataKey.imageIndex: currentIndex,
                            MetadataKey.imageCount: frames.count,
                            MetadataKey.isLooping: isLooping
                        ]) { current, _ in current }
                    )
                    let frame = PixelBufferFrame(pixelBuffer: pixelBuffer, metadata: metadata)
                    callbackQueue.async {
                        self.delegate?.mediaSource(self, didOutput: frame)
                        self.outputNode.transmit(frame) { _ in }
                    }
                    currentPresentationTime = currentPresentationTime + item.duration
                    currentIndex += 1
                } catch {
                    callbackQueue.async {
                        self.delegate?.mediaSource(self, didFail: error)
                        self.delegate?.mediaSourceDidFinish(self)
                    }
                    return
                }
            }

            if isLooping && !frames.isEmpty && !shouldStop && !isCancelled {
                currentIndex = 0
                continue
            }
            break
        } while true

        callbackQueue.async {
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    private func waitIfNeeded() {
        pauseCondition.lock()
        while isPaused && !shouldStop && !isCancelled {
            pauseCondition.wait()
        }
        pauseCondition.unlock()
    }

    private static func makePixelBuffer(from image: CGImage, renderSize: CGSize?) throws -> CVPixelBuffer {
        let width = max(Int(renderSize?.width ?? CGFloat(image.width)), 1)
        let height = max(Int(renderSize?.height ?? CGFloat(image.height)), 1)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw VideoX.Error.newRenderedPixelBufferForRequestFailure
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw VideoX.Error.newRenderedPixelBufferForRequestFailure
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw VideoX.Error.newRenderedPixelBufferForRequestFailure
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    public func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }
}
