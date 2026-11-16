//
//  CameraVideoFormatSelectionTests.swift
//  KakaposCameraTests
//
//  Created by Condy on 2026/11/16.
//

import AVFoundation
import CoreVideo
import KakaposCamera
import XCTest

final class CameraVideoFormatSelectionTests: XCTestCase {
    private func candidate(_ width: Int, _ height: Int, _ min: Double, _ max: Double) -> CameraVideoFormatCandidate {
        .init(width: width, height: height, frameRateRanges: [.init(minimumFramesPerSecond: min, maximumFramesPerSecond: max)])
    }

    func testStrictSelectionFindsWholeSizeAndRateCombination() throws {
        var request = CameraVideoConfiguration(preferredFrameRateRange: .init(minimumFramesPerSecond: 60, maximumFramesPerSecond: 60),
            formatSelectionPolicy: .requireRequested, captureDimensions: CGSize(width: 3840, height: 2160))
        let formats = [candidate(1920, 1080, 1, 120), candidate(3840, 2160, 1, 30), candidate(3840, 2160, 1, 60)]
        XCTAssertEqual(try request.preferredFormatIndex(in: formats, currentIndex: 1), 2)
        request.preferredFrameRateRange = .init(minimumFramesPerSecond: 24, maximumFramesPerSecond: 24)
        XCTAssertEqual(try request.preferredFormatIndex(in: formats, currentIndex: 2), 2)
        XCTAssertThrowsError(try request.preferredFormatIndex(in: [formats[0]])) {
            XCTAssertEqual($0 as? CameraVideoSpecificationError, .unsupportedSpecification)
        }
        request.preferredFrameRateRange = .init(minimumFramesPerSecond: 60, maximumFramesPerSecond: 60)
        XCTAssertThrowsError(try request.preferredFormatIndex(in: [formats[1]]))
    }

    func testBestEffortDefaultsDoNotTakeOverLegacySelection() throws {
        let request = CameraVideoConfiguration()
        XCTAssertEqual(request.formatSelectionPolicy, .bestEffort)
        XCTAssertNil(request.captureDimensions)
        XCTAssertNil(try request.preferredFormatIndex(in: []))
        XCTAssertTrue(request.accepts(.init(width: 1280, height: 720, minimumFrameRate: nil, maximumFrameRate: nil,
            pixelFormat: nil, stabilizationMode: nil, deviceIdentifier: "legacy")))
    }

    func testReadbackMismatchIsNotAcceptedAsRequestedSpecification() throws {
        let request = CameraVideoConfiguration(preferredFrameRateRange: .init(minimumFramesPerSecond: 60, maximumFramesPerSecond: 60),
            formatSelectionPolicy: .requireRequested, captureDimensions: CGSize(width: 3840, height: 2160))
        let expected = CameraVideoSpecification(width: 3840, height: 2160, minimumFrameRate: 60, maximumFrameRate: 60,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, stabilizationMode: 0, deviceIdentifier: "back")
        XCTAssertTrue(request.accepts(expected))
        XCTAssertFalse(request.accepts(.init(width: 3840, height: 2160, minimumFrameRate: 30, maximumFrameRate: 30,
            pixelFormat: nil, stabilizationMode: nil, deviceIdentifier: "back")))
        XCTAssertFalse(request.accepts(.init(width: 1920, height: 1080, minimumFrameRate: 60, maximumFrameRate: 60,
            pixelFormat: nil, stabilizationMode: nil, deviceIdentifier: "back")))
        XCTAssertEqual(try JSONDecoder().decode(CameraVideoSpecification.self, from: JSONEncoder().encode(expected)), expected)
    }

    func testIntegerAndNTSCFrameDurationsAreExact() throws {
        for fps: Int32 in [18, 24, 30, 60] {
            let durations = try CameraFrameRateRange(minimumFramesPerSecond: Double(fps), maximumFramesPerSecond: Double(fps)).frameDurations()
            XCTAssertEqual(CMTimeCompare(durations.minimum, CMTime(value: 1, timescale: fps)), 0)
            XCTAssertEqual(durations.minimum, durations.maximum)
            XCTAssertFalse(durations.minimum.flags.contains(.hasBeenRounded))
            XCTAssertEqual(1 / durations.minimum.seconds, Double(fps), accuracy: 1e-10)
        }
        let ntsc = try CameraFrameRateRange(minimumFramesPerSecond: 24_000.0 / 1001, maximumFramesPerSecond: 60_000.0 / 1001).frameDurations()
        XCTAssertEqual(ntsc.minimum, CMTime(value: 1001, timescale: 60_000))
        XCTAssertEqual(ntsc.maximum, CMTime(value: 1001, timescale: 24_000))
        let decimal = try CameraFrameRateRange(minimumFramesPerSecond: 29.97, maximumFramesPerSecond: 29.97).frameDurations()
        XCTAssertEqual(CMTimeCompare(decimal.minimum, CMTime(value: 100, timescale: 2997)), 0)
    }

    func testInvalidFrameRatesAndDimensionsAreRejected() {
        for range in [CameraFrameRateRange(minimumFramesPerSecond: 0, maximumFramesPerSecond: 30),
                      .init(minimumFramesPerSecond: 60, maximumFramesPerSecond: 30),
                      .init(minimumFramesPerSecond: .nan, maximumFramesPerSecond: 60),
                      .init(minimumFramesPerSecond: 30, maximumFramesPerSecond: .infinity)] {
            XCTAssertThrowsError(try range.frameDurations())
        }
        for size in [CGSize.zero, CGSize(width: 1920.5, height: 1080), CGSize(width: CGFloat.infinity, height: 1080)] {
            let request = CameraVideoConfiguration(formatSelectionPolicy: .requireRequested, captureDimensions: size)
            XCTAssertThrowsError(try request.preferredFormatIndex(in: []))
        }
    }
}
