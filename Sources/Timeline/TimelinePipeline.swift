//
//  TimelinePipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation
import AVFoundation

public final class TimelinePipeline {
    public struct Summary {
        public let renderSize: CGSize
        public let frameDuration: CMTime
        public let layerCount: Int
        public let transitionCount: Int
        public let compiledSummaryText: String

        public var summaryText: String {
            let sizeText = "\(Int(renderSize.width))x\(Int(renderSize.height))"
            let frameRateText = frameDuration.timescale > 0
                ? "\(frameDuration.timescale)fps"
                : "fps n/a"
            return "size \(sizeText) · frame \(frameRateText) · layers \(layerCount) · transitions \(transitionCount) · \(compiledSummaryText)"
        }
    }

    public let composition: TimelineComposition

    public var layers: [TimelineLayer] {
        get { composition.layers }
        set { composition.layers = newValue }
    }

    public var transitions: [Transition] {
        get { composition.transitions }
        set { composition.transitions = newValue }
    }

    public var renderSize: CGSize {
        composition.renderSize
    }

    public var frameDuration: CMTime {
        composition.frameDuration
    }

    public var summary: Summary {
        let compiled = compile()
        return Summary(
            renderSize: composition.renderSize,
            frameDuration: composition.frameDuration,
            layerCount: composition.layers.count,
            transitionCount: composition.transitions.count,
            compiledSummaryText: compiled.summary.summaryText
        )
    }

    public var summaryText: String {
        summary.summaryText
    }

    public init(
        renderSize: CGSize = CGSize(width: 720, height: 1280),
        frameDuration: CMTime = CMTime(value: 1, timescale: 30),
        layers: [TimelineLayer] = [],
        transitions: [Transition] = []
    ) {
        self.composition = TimelineComposition(
            renderSize: renderSize,
            frameDuration: frameDuration,
            layers: layers,
            transitions: transitions
        )
    }

    public init(composition: TimelineComposition) {
        self.composition = composition
    }

    public func addLayer(_ layer: TimelineLayer) {
        composition.addLayer(layer)
    }

    public func addTransition(_ transition: Transition) {
        composition.addTransition(transition)
    }

    public func compile() -> CompiledTimelineComposition {
        composition.compile()
    }
}
