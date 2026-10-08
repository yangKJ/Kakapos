//
//  CameraRuntimeRegressionTests.swift
//  Kakapos
//
//  Created by Condy on 2026/10/7.
//

import XCTest

@testable import KakaposCamera

final class CameraRuntimeRegressionTests: XCTestCase {
    func testIngressCapacitySeparatesAudioAndVideoDrops() {
        let gate = CameraFrameIngressGate(maximumInFlightFrameCount: 1, maximumInFlightAudioFrameCount: 1)
        gate.reset()
        XCTAssertNotNil(gate.admit(mediaKind: .video, branchCount: 1))
        XCTAssertNotNil(gate.admit(mediaKind: .audio, branchCount: 1))
        XCTAssertNil(gate.admit(mediaKind: .video, branchCount: 1))
        XCTAssertEqual(gate.snapshot.droppedVideoFrameCount, 1)
        XCTAssertEqual(gate.snapshot.droppedAudioFrameCount, 0)
    }
}
