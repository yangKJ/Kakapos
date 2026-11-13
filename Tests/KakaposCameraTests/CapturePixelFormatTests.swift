//
//  CapturePixelFormatTests.swift
//  KakaposCameraTests
//
//  Created by Condy on 2026/11/14.
//

import AVFoundation
import CoreVideo
import XCTest
import KakaposCamera
import KakaposMediaCore
import KakaposVideo

final class CapturePixelFormatTests: XCTestCase {
    func testPreferredPixelFormatsPreserveDefaultsAndHDRRequirements() {
        var configuration = CameraVideoConfiguration()
        let formats: [OSType] = [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        XCTAssertEqual(configuration.resolvedPixelFormat(available: formats), kCVPixelFormatType_32BGRA)
        configuration.preferredPixelFormats = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        XCTAssertEqual(configuration.resolvedPixelFormat(available: formats), kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        XCTAssertEqual(configuration.resolvedPixelFormat(available: [kCVPixelFormatType_32BGRA]), kCVPixelFormatType_32BGRA)
        configuration.colorPolicy = .hdrHLG
        XCTAssertNil(configuration.resolvedPixelFormat(available: formats))
        XCTAssertEqual(configuration.resolvedPixelFormat(available: [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]),
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    }

    func testRecorderAcceptsNativeBiPlanarInputAndFinishesReadableMovie() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-420-" + UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = try RecorderSink(outputURL: url, fileType: .mp4)
        for index in 0..<3 {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            for plane in 0..<2 {
                let address = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixels, plane))
                memset(address, plane == 0 ? 100 : 128,
                    CVPixelBufferGetBytesPerRowOfPlane(pixels, plane) * CVPixelBufferGetHeightOfPlane(pixels, plane))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            CVBufferSetAttachment(pixels, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pixels, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pixels, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            let frame = PixelBufferFrame(pixelBuffer: pixels, metadata: FrameMetadata(presentationTime: CMTime(value: Int64(index), timescale: 24),
                duration: CMTime(value: 1, timescale: 24)))
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sink.consume(frame) { continuation.resume(with: $0) }
            }
            try await Task.sleep(nanoseconds: 45_000_000)
        }
        let completed = expectation(description: "原生格式录制封口")
        sink.finishRecording { result in
            if case .failure(let error) = result { XCTFail(String(describing: error)) }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }
}
