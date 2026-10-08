//
//  HDRArtifactContractTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/07.
//

import AVFoundation
import CoreImage
import CoreVideo
import VideoToolbox
import XCTest

@testable import Kakapos
@testable import KakaposMediaCore
@testable import KakaposTimeline
@testable import KakaposVideo

final class HDRArtifactContractTests: XCTestCase {
    func testReaderWriterReencodesHLGArtifactWithRealHDRPixels() throws {
        try assertHDRExport(policy: .hdrHLG, transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG)
    }

    func testReaderWriterReencodesPQArtifactWithRealHDRPixels() throws {
        try assertHDRExport(policy: .hdrPQ, transfer: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)
    }

    func testHDRProfileRejectsH264() throws {
        let url = try makeHDRFixture(transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG)
        defer { try? FileManager.default.removeItem(at: url) }
        let job = ReaderWriterExportJob(
            asset: AVAsset(url: url),
            outputURL: temporaryURL(extension: "mp4"),
            videoProcessors: [PassthroughFrameProcessor()],
            exportProfile: .init(videoCodec: .h264, colorPolicy: .hdrHLG)
        )
        let expectation = expectation(description: "h264 rejected")
        job.export { result in
            guard case .failure = result else { return XCTFail("HDR must reject H.264") }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testHDRProfileRejectsProcessorWithoutHDRCapability() throws {
        let url = try makeHDRFixture(transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = temporaryURL(extension: "mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let job = ReaderWriterExportJob(
            asset: AVAsset(url: url), outputURL: output,
            videoProcessors: [StandardDynamicRangeFrameProcessor()],
            exportProfile: .init(videoCodec: .hevc, colorPolicy: .hdrHLG)
        )
        let expectation = expectation(description: "processor rejected")
        job.export { result in
            guard case .failure = result else { return XCTFail("non-HDR processor must fail closed") }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }

    func testHLGAndPQPartialEffectsPreserveLinearHighlights() throws {
        for transfer in [
            kCVImageBufferTransferFunction_ITU_R_2100_HLG, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        ] {
            let input = try makeHDRBuffer(transfer: transfer, brightness: 2)
            let processed = try makeHDRBuffer(transfer: transfer, brightness: 4)
            let effect = EffectLayer(
                timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
                source: EffectSource(processor: HDRBufferProcessor(buffer: processed), intensity: 0.5))
            let stage = try XCTUnwrap(TimelinePipeline(layers: [effect]).compile().timelineProcessors.first)
            let done = expectation(description: "HDR 线性光混合")
            stage.process(PixelBufferFrame(pixelBuffer: input, metadata: FrameMetadata(presentationTime: .zero))) {
                result in
                do {
                    let frame = try result.get()
                    let output = try XCTUnwrap(extractPixelBuffer(frame))
                    let expected = (self.linearHighlight(input) + self.linearHighlight(processed)) * 0.5
                    XCTAssertEqual(self.linearHighlight(output), expected, accuracy: 0.12)
                    XCTAssertEqual(
                        FrameFormat(pixelBuffer: output).dynamicRange, FrameFormat(pixelBuffer: input).dynamicRange)
                } catch { XCTFail("HDR 混合失败：\(error)") }
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
    }

    func testHLGToPQConversionPreservesHighlightValues() throws {
        let input = try makeHDRBuffer(transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG, brightness: 2)
        let done = expectation(description: "HLG 转 PQ")
        VideoColorConversionProcessor(policy: .hdrPQ).process(
            PixelBufferFrame(pixelBuffer: input, metadata: FrameMetadata(presentationTime: .zero))
        ) { result in
            do {
                let output = try XCTUnwrap(extractPixelBuffer(try result.get()))
                XCTAssertEqual(FrameFormat(pixelBuffer: output).dynamicRange, .hdr(.pq))
                XCTAssertEqual(self.linearHighlight(output), self.linearHighlight(input), accuracy: 0.12)
            } catch { XCTFail("色彩转换失败：\(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testHDRPreviewRejectsUndeclaredProcessors() {
        let plan = FrameProcessingPlan(identity: .init(identifier: "hdr-rejection", revision: "1"), makeProcessors: {
            [ClosureFrameProcessor { frame, completion in completion(.success(frame)) }]
        })
        XCTAssertThrowsError(try VideoPreviewProcessingLane(generation: .init(rawValue: 1), mode: .processed(plan), colorPolicy: .hdrHLG, output: { _, _, _ in }))
    }

    func testHDRPreviewRejectsSDROutputDespiteHDRMetadata() throws {
        let input = try makeHDRBuffer(transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG)
        var sdr: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &sdr)
        let sdrBuffer = try XCTUnwrap(sdr)
        let plan = FrameProcessingPlan(identity: .init(identifier: "hdr-output-validation", revision: "1"), makeProcessors: {
            [HDRBufferProcessor(buffer: sdrBuffer)]
        })
        let failed = expectation(description: "HDR 预览拒绝伪装输出")
        let lane = try VideoPreviewProcessingLane(generation: .init(rawValue: 1), mode: .processed(plan), colorPolicy: .hdrHLG) { _, _, _ in
            XCTFail("SDR 输出不能成为 HDR 预览成功帧")
        }
        lane.errorHandler = { _ in failed.fulfill() }
        lane.consume(PixelBufferFrame(pixelBuffer: input, metadata: FrameMetadata(presentationTime: .zero)))
        wait(for: [failed], timeout: 5)
        lane.cancel()
    }

    private func assertHDRExport(policy: VideoExportColorPolicy, transfer: CFString) throws {
        let sourceURL = try makeHDRFixture(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let outputURL = temporaryURL(extension: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let job = ReaderWriterExportJob(
            asset: AVAsset(url: sourceURL), outputURL: outputURL,
            videoProcessors: TimelinePipeline(layers: [
                EffectLayer(timeRange: CMTimeRange(start: .zero, duration: .positiveInfinity),
                    source: EffectSource(makeProcessor: { PassthroughFrameProcessor() }, intensity: 0.5))
            ]).compile().timelineProcessors,
            exportProfile: .init(videoCodec: .hevc, colorPolicy: policy)
        )
        let expectation = expectation(description: "HDR export")
        var result: Result<URL, Error>?
        job.export {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 20)
        let artifact = try XCTUnwrap(result).get()
        let asset = AVAsset(url: artifact)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let description = try XCTUnwrap(track.formatDescriptions.first) as! CMFormatDescription
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_HEVC)
        XCTAssertTrue(CMFormatDescriptionGetExtensions(description) != nil)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            ])
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        XCTAssertEqual(FrameFormat(pixelBuffer: buffer).dynamicRange, policy == .hdrHLG ? .hdr(.hlg) : .hdr(.pq))
        assertHighlight(buffer)
        if let directory = ProcessInfo.processInfo.environment["KAKAPOS_ACCEPTANCE_ARTIFACT_DIRECTORY"] {
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent(policy == .hdrHLG ? "timeline-half-hlg.mp4" : "timeline-half-pq.mp4")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: artifact, to: target)
        }
    }

    private func makeHDRFixture(transfer: CFString) throws -> URL {
        let url = temporaryURL(extension: "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
                AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel],
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020, AVVideoTransferFunctionKey: transfer,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ],
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let buffer = try makeHDRBuffer(transfer: transfer)
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertTrue(input.isReadyForMoreMediaData)
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 30))
        input.markAsFinished()
        let done = expectation(description: "fixture writer")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func makeHDRBuffer(transfer: CFString, brightness: CGFloat = 2) throws -> CVPixelBuffer {
        guard #available(iOS 14.1, tvOS 14.2, macOS 12, watchOS 7.1, *) else { throw XCTSkip("系统不支持 HDR 色彩转换 API") }
        var buffer: CVPixelBuffer?
        let attrs =
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:], kCVPixelBufferMetalCompatibilityKey as String: true]
            as [String: Any]
        XCTAssertEqual(
            CVPixelBufferCreate(
                nil, 64, 64, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, attrs as CFDictionary, &buffer),
            kCVReturnSuccess)
        let value = try XCTUnwrap(buffer)
        let destination = CGColorSpace(
            name: transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG
                ? CGColorSpace.itur_2100_HLG : CGColorSpace.itur_2100_PQ)!
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAh])
        let color = CIColor(red: brightness, green: brightness, blue: brightness, alpha: 1, colorSpace: linear)!
        context.render(
            CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)), to: value,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64), colorSpace: destination)
        CVBufferSetAttachment(
            value, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(value, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate)
        CVBufferSetAttachment(
            value, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
        CVBufferSetAttachment(value, kCVImageBufferCGColorSpaceKey, destination, .shouldPropagate)
        return value
    }

    private func assertHighlight(_ buffer: CVPixelBuffer) {
        XCTAssertGreaterThan(linearHighlight(buffer), 1.2, "HDR 高光必须在重新解码后仍超出 SDR 白点")
    }

    private func linearHighlight(_ buffer: CVPixelBuffer) -> Float {
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf])
        var pixels = [Float](repeating: 0, count: 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                CIImage(cvPixelBuffer: buffer), toBitmap: bytes.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: linear)
        }
        return pixels[0]
    }

    private func temporaryURL(extension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(
            `extension`)
    }
}

private struct HDRBufferProcessor: FrameProcessor, FrameProcessorCapabilityProviding {
    let buffer: CVPixelBuffer
    let capabilities = FrameProcessorCapabilities(supportedDynamicRanges: [.hdr(.hlg), .hdr(.pq)])
    func process(_ frame: MediaFrame, completion: @escaping (Result<MediaFrame, Error>) -> Void) {
        completion(.success(PixelBufferFrame(pixelBuffer: buffer, metadata: frame.metadata)))
    }
}
