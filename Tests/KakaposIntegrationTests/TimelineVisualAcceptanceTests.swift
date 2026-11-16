// 作者：Condy
#if os(macOS)
import AVFoundation
import CoreImage
import CoreText
import XCTest
@testable import KakaposMediaCore
@testable import KakaposTimeline
import KakaposVideo

final class TimelineVisualAcceptanceTests: XCTestCase {
    private var files: [URL] = []
    override func tearDown() { files.forEach { try? FileManager.default.removeItem(at: $0) }; super.tearDown() }
    private func clip(_ url: URL, level: Int = 0) -> ClipLayer {
        ClipLayer(asset: AVURLAsset(url: url), timeRange: Round2Fixtures.range(0, 2), sourceTimeRange: Round2Fixtures.range(0, 2), layerLevel: level)
    }
    private func source() throws -> URL { let url = try Round2Fixtures.movie(self); files.append(url); return url }
    private func image(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1, width: Int = 64, height: Int = 64) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height)); return try XCTUnwrap(context.makeImage())
    }
    private func export(_ layers: [TimelineLayer], transitions: [Transition] = [], profile: VideoExportProfile = .legacyCompatible) throws -> URL {
        var compiled = TimelineComposition(renderSize: CGSize(width: 64, height: 64), layers: layers, transitions: transitions).compile()
        XCTAssertTrue(compiled.isValid, "\(compiled.diagnostics)"); compiled.exportProfile = profile
        let output = Round2Fixtures.url(); files.append(output)
        let job = compiled.makeExportJob(outputURL: output)
        let done = expectation(description: "真实视觉产物导出")
        job.export { result in if case .failure(let error) = result { XCTFail("\(error)") }; done.fulfill() }
        wait(for: [done], timeout: 15); XCTAssertEqual(job.status, .completed)
        return output
    }
    private func pixel(_ url: URL, at seconds: Double, x: Int = 32, y: Int = 32) throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let cg = try generator.copyCGImage(at: Round2Fixtures.time(seconds), actualTime: nil)
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let p = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self) + (y * 64 + x) * 4
        return [Int(p[0]), Int(p[1]), Int(p[2])]
    }
    func testIdenticalFramesRemainConstantThroughDissolve() throws {
        let input = try source()
        let baseline = try export([clip(input)])
        let result = try export([clip(input), clip(input, level: 1)], transitions: [.init(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)])
        for time in [0.0, 0.25, 0.75, 1.0, 1.75] {
            let actual = try pixel(result, at: time); let expected = try pixel(baseline, at: time)
            for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(actual[channel] - expected[channel]), 12, "t=\(time)") }
        }
    }
    func testDissolveDirectionAndEasingReachRealFrames() throws {
        let red = try source(); let blue = try Round2Fixtures.movie(self, colorIndex: 2); files.append(blue)
        let linear = try export([clip(red), clip(blue, level: 1)], transitions: [
            .init(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)
        ])
        let eased = try export([clip(red), clip(blue, level: 1)], transitions: [
            .init(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1, timingFunction: .easeIn)
        ])
        XCTAssertGreaterThan(try pixel(linear, at: 0)[0], 220)
        let end = try pixel(linear, at: 1.9); XCTAssertGreaterThan(end[2], end[0] + 100)
        let a = try pixel(linear, at: 1); let b = try pixel(eased, at: 1)
        XCTAssertGreaterThan(b[0], a[0] + 10); XCTAssertLessThan(b[2], a[2] - 20)
    }
    func testInvalidTextGeometryFailsCompilationInsteadOfDroppingContent() {
        let text = TextLayer(attributedText: NSAttributedString(string: "文字"), frame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 64),
            timeRange: Round2Fixtures.range(0, 1))
        let compiled = TimelineComposition(layers: [text]).compile()
        XCTAssertFalse(compiled.isValid); XCTAssertFalse(compiled.diagnostics.isEmpty)
    }
    func testSequentialDissolvesDoNotDimIdenticalFrames() throws {
        let input = try source()
        let output = try export([clip(input), clip(input, level: 1), clip(input, level: 2)], transitions: [
            .init(timeRange: Round2Fixtures.range(0, 0.5), sourceLayerLevel: 0, destinationLayerLevel: 1),
            .init(timeRange: Round2Fixtures.range(1, 0.5), sourceLayerLevel: 1, destinationLayerLevel: 2)
        ])
        for time in [0.25, 0.75, 1.25, 1.75] { XCTAssertGreaterThan(try pixel(output, at: time)[0], 220) }
    }
    func testDissolveInterpolatesPremultipliedAlphaOverBackground() throws {
        let input = try source()
        let a = clip(input); let b = clip(input, level: 1); a.opacity = 0.5; b.opacity = 0.5
        let green = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 2), layerLevel: -1)
        let compiled = TimelineComposition(renderSize: CGSize(width: 64, height: 64), layers: [a, b, green], transitions: [
            .init(timeRange: Round2Fixtures.range(0, 2), sourceLayerLevel: 0, destinationLayerLevel: 1)
        ]).compile()
        let instruction = try XCTUnwrap(compiled.videoComposition.instructions.first as? TimelineVideoInstruction)
        let red = try Round2Fixtures.frame(0).pixelBuffer; let blue = try Round2Fixtures.frame(2).pixelBuffer
        let ids = compiled.renderPlan.assetSegments.compactMap(\.compositionTrackID)
        for buffer in [red, blue] { CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate) }
        let result = try TimelineVisualRenderer.image(in: instruction, at: Round2Fixtures.time(1), size: CGSize(width: 64, height: 64)) { $0 == ids[0] ? red : blue }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        var rgba = [Float](repeating: 0, count: 4)
        context.render(result, toBitmap: &rgba, rowBytes: 16, bounds: CGRect(x: 32, y: 32, width: 1, height: 1), format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        var background = [Float](repeating: 0, count: 4)
        context.render(CIImage(cgImage: green.image), toBitmap: &background, rowBytes: 16, bounds: CGRect(x: 32, y: 32, width: 1, height: 1), format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        XCTAssertEqual(rgba[0], 0.25, accuracy: 0.025); XCTAssertEqual(rgba[1], background[1] * 0.5, accuracy: 0.015)
        XCTAssertEqual(rgba[2], 0.25, accuracy: 0.025); XCTAssertEqual(rgba[3], 1, accuracy: 0.01)
    }
    func testImageLayerIsRenderedOnlyInsideItsWindow() throws {
        let input = try source()
        let overlay = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0.5, 1), layerLevel: 1)
        let output = try export([clip(input), overlay])
        for time in [0.25, 1.5, 1.75] { XCTAssertGreaterThan(try pixel(output, at: time)[0], 220) }
        for time in [0.5, 0.75, 1.25] { XCTAssertGreaterThan(try pixel(output, at: time)[1], 230) }
    }
    func testImageCanSitBehindVideoAndBlendItsOwnOpacity() throws {
        let input = try source()
        let behind = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 2), layerLevel: -1)
        XCTAssertGreaterThan(try pixel(export([behind, clip(input)]), at: 1)[0], 220)
        let front = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 2), layerLevel: 1); front.opacity = 0.5
        let value = try pixel(export([clip(input), front]), at: 1)
        XCTAssertGreaterThan(value[0], 100); XCTAssertGreaterThan(value[1], 100)
    }
    func testImagesOnlyTimelinePreservesInitialGapAndTail() throws {
        let first = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0.5, 0.5))
        let second = ImageLayer(image: try image(0, 0, 1), timeRange: Round2Fixtures.range(1.5, 0.5))
        let output = try export([first, second])
        XCTAssertEqual(AVURLAsset(url: output).duration.seconds, 2, accuracy: 0.05)
        for time in [0.25, 1.25] { XCTAssertLessThan(try pixel(output, at: time).max()!, 10) }
        XCTAssertGreaterThan(try pixel(output, at: 0.75)[1], 230); XCTAssertGreaterThan(try pixel(output, at: 1.75)[2], 230)
    }
    func testImageTailExtendsVideoComposition() throws {
        let input = try source()
        let tail = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(2, 1))
        let output = try export([clip(input), tail])
        XCTAssertEqual(AVURLAsset(url: output).duration.seconds, 3, accuracy: 0.05)
        XCTAssertGreaterThan(try pixel(output, at: 2.5)[1], 230)
    }
    func testImageGroupTransformAndOpacityKeyframesReachPixels() throws {
        let overlay = ImageLayer(image: try image(0, 1, 0, width: 16, height: 16), timeRange: Round2Fixtures.range(0, 2))
        overlay.keyframes = [.init(keyPath: "translation.x", values: [0, 32], keyTimes: [.zero, Round2Fixtures.time(2)])]
        let group = GroupLayer(timeRange: Round2Fixtures.range(0, 2), layers: [overlay]); group.transform = CGAffineTransform(translationX: 0, y: 16)
        let output = try export([group])
        // 位图行从顶端开始；时间线正 y 向下。
        XCTAssertGreaterThan(try pixel(output, at: 0.5, x: 16, y: 24)[1], 200)
        XCTAssertLessThan(try pixel(output, at: 0.5, x: 48, y: 24)[1], 15)
        XCTAssertGreaterThan(try pixel(output, at: 1.5, x: 32, y: 24)[1], 200)
    }
    func testTextWindowRemainsHardGatedWithAndWithoutKeyframes() throws {
        let input = try source()
        for keyframes in [false, true] {
            let text = TextLayer(attributedText: NSAttributedString(string: ""), frame: CGRect(x: 0, y: 0, width: 64, height: 64),
                timeRange: Round2Fixtures.range(0.5, 1), layerLevel: 2, backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            if keyframes { text.keyframes = [.init(keyPath: "opacity", values: [1, 1], keyTimes: [Round2Fixtures.time(0.5), Round2Fixtures.time(1.5)])] }
            let output = try export([clip(input), text])
            for time in [0.25, 1.5, 1.75] { XCTAssertGreaterThan(try pixel(output, at: time)[0], 220) }
            for time in [0.5, 0.75, 1.25] { XCTAssertGreaterThan(try pixel(output, at: time)[1], 230) }
        }
    }
    func testTextOnlyTimelineUsesSameCompositionAsImages() throws {
        let text = TextLayer(attributedText: NSAttributedString(string: ""), frame: CGRect(x: 0, y: 0, width: 64, height: 64),
            timeRange: Round2Fixtures.range(0.5, 1), backgroundColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        let output = try export([text]); XCTAssertLessThan(try pixel(output, at: 0.25)[1], 15)
        XCTAssertGreaterThan(try pixel(output, at: 1)[1], 230)
    }
    func testImagesAndTextShareLayerOrder() throws {
        let green = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 2), layerLevel: 2)
        let text = TextLayer(attributedText: NSAttributedString(string: ""), frame: CGRect(x: 0, y: 0, width: 64, height: 64),
            timeRange: Round2Fixtures.range(0, 2), layerLevel: 1, backgroundColor: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertGreaterThan(try pixel(export([green, text]), at: 1)[1], 230)
    }
    func testAttributedParagraphStyleSurvivesFallbackAlignment() throws {
        let text = NSMutableAttributedString(string: "A\nB", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 16, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)
        ])
        var alignment = CTTextAlignment.right
        withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            text.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: CTParagraphStyleCreate(&setting, 1), range: NSRange(location: 2, length: 1))
        }
        let layer = TextLayer(attributedText: text, frame: CGRect(x: 0, y: 0, width: 64, height: 64), timeRange: Round2Fixtures.range(0, 1))
        let rendered = try TimelineTextContent(layer).image(at: 0)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        CIContext().render(rendered, toBitmap: &pixels, rowBytes: 256, bounds: CGRect(x: 0, y: 0, width: 64, height: 64), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let left = (0..<4096).filter { $0 % 64 < 16 && pixels[$0 * 4 + 3] > 100 }.count
        let right = (0..<4096).filter { $0 % 64 > 48 && pixels[$0 * 4 + 3] > 100 }.count
        XCTAssertGreaterThan(left, 5); XCTAssertGreaterThan(right, 5)
    }
    func testGroupTransformAlsoMovesTextFrameOrigin() throws {
        let text = TextLayer(attributedText: NSAttributedString(string: ""), frame: CGRect(x: 8, y: 8, width: 16, height: 16),
            timeRange: Round2Fixtures.range(0, 1), backgroundColor: CGColor(gray: 1, alpha: 1))
        let group = GroupLayer(timeRange: Round2Fixtures.range(0, 1), layers: [text]); group.transform = CGAffineTransform(scaleX: 2, y: 2)
        let output = try export([group])
        XCTAssertGreaterThan(try pixel(output, at: 0.5, x: 44, y: 32)[0], 220)
        XCTAssertLessThan(try pixel(output, at: 0.5, x: 12, y: 32)[0], 15)
    }
    func testRealTextGlyphsSurviveRasterizationAndGroupOpacity() throws {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 40, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)
        ]
        let text = TextLayer(attributedText: NSAttributedString(string: "M", attributes: attributes),
            frame: CGRect(x: 0, y: 0, width: 64, height: 64), timeRange: Round2Fixtures.range(0, 1))
        let normal = try export([text])
        let group = GroupLayer(timeRange: Round2Fixtures.range(0, 1), layers: [text]); group.opacity = 0.5
        let faded = try export([group])
        func maximumRed(_ url: URL) throws -> Int {
            let image = try AVAssetImageGenerator(asset: AVURLAsset(url: url)).copyCGImage(at: Round2Fixtures.time(0.5), actualTime: nil)
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return (0..<(64 * 64)).map { Int(bytes[$0 * 4]) }.max() ?? 0
        }
        let peak = try maximumRed(normal); let fadedPeak = try maximumRed(faded)
        XCTAssertGreaterThan(peak, 220); XCTAssertGreaterThan(fadedPeak, 130); XCTAssertLessThan(fadedPeak, peak - 20)
    }
    func testStillTailKeepsClipAudioAndExplicitSilence() throws {
        let layer = ClipLayer(asset: Round2Fixtures.asset(), timeRange: Round2Fixtures.range(0, 2), sourceTimeRange: Round2Fixtures.range(0, 2))
        let tail = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(2, 1))
        let output = try export([layer, tail])
        XCTAssertEqual(AVURLAsset(url: output).tracks(withMediaType: .audio).count, 1)
        XCTAssertGreaterThan(try pixel(output, at: 2.5)[1], 230)
    }
    func testVisualCompositionKeepsP3ColorProperties() throws {
        let overlay = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 0.5))
        let output = try export([overlay], profile: .init(videoCodec: .hevc, colorPolicy: .standardDisplayP3))
        let format = try VideoAssetProfileInspector().inspect(AVURLAsset(url: output)).frameFormat
        XCTAssertEqual(format.colorInfo.primaries, .p3D65); XCTAssertEqual(format.dynamicRange, .standard)
    }
    func testVisualCompositionKeepsHDRTenBitArtifactContract() throws {
        for policy: VideoExportColorPolicy in [.hdrHLG, .hdrPQ] {
            let overlay = ImageLayer(image: try image(0, 1, 0), timeRange: Round2Fixtures.range(0, 0.5))
            let output = try export([overlay], profile: .init(videoCodec: .hevc, colorPolicy: policy))
            let report = try VideoArtifactValidator.validate(url: output, expectation: .init(sourceDuration: Round2Fixtures.time(0.5), expectsAudio: false,
                expectedVideoCodec: .hevc, expectedDynamicRange: policy.requestedDynamicRange, expectedVideoSize: CGSize(width: 64, height: 64)))
            XCTAssertEqual(report.dynamicRange, policy.requestedDynamicRange)
            let asset = AVURLAsset(url: output); let reader = try AVAssetReader(asset: asset)
            let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
            let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
            reader.add(decoded); XCTAssertTrue(reader.startReading())
            let sample = try XCTUnwrap(decoded.copyNextSampleBuffer()); let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(FrameFormat(pixelBuffer: buffer).pixelFormat, .yuv420BiPlanar10BitVideoRange)
            XCTAssertEqual(FrameFormat(pixelBuffer: buffer).dynamicRange, policy.requestedDynamicRange)
            reader.cancelReading()
        }
    }
}
#endif
