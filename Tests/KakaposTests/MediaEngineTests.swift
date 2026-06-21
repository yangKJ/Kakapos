import XCTest
import AVFoundation
import CoreGraphics
@testable import Kakapos

final class MediaEngineTests: XCTestCase {

    func testPassthroughFrameProcessorPreservesPixelBufferMetadata() throws {
        let pixelBuffer = try makePixelBuffer(width: 16, height: 16)
        let metadata = FrameMetadata(
            presentationTime: CMTime(value: 12, timescale: 30),
            duration: CMTime(value: 1, timescale: 30),
            sourceTime: CMTime(value: 10, timescale: 30),
            trackTransform: .identity,
            frameIndex: 7
        )
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata)
        let expectation = self.expectation(description: "processor returns frame")

        PassthroughFrameProcessor().process(frame) { result in
            switch result {
            case .success(let output):
                XCTAssertEqual(output.metadata.presentationTime, metadata.presentationTime)
                XCTAssertEqual(output.metadata.duration, metadata.duration)
                XCTAssertEqual(output.metadata.sourceTime, metadata.sourceTime)
                XCTAssertEqual(output.metadata.frameIndex, metadata.frameIndex)
                XCTAssertEqual(CVPixelBufferGetWidth(output.pixelBuffer!), 16)
            case .failure(let error):
                XCTFail("Unexpected processor failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testMediaPipelineProcessesSourceFramesIntoSink() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let source = TestSource(frames: [input])
        let sink = TestSink()
        let processor = ClosureFrameProcessor { frame, completion in
            var output = frame
            output.metadata.frameIndex = 2
            completion(.success(output))
        }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])

        pipeline.start()

        XCTAssertEqual(sink.frames.count, 1)
        XCTAssertEqual(sink.frames.first?.metadata.frameIndex, 2)
    }

    func testImageSourceCanBroadcastFramesDirectlyToConsumerNode() throws {
        let frame = StillImageFrame(image: try makeImage(width: 16, height: 16))
        let source = ImageSource(frames: [frame], callbackQueue: .main)
        let consumer = TestConsumerNode()
        let completion = expectation(description: "direct source-consumer delivery")

        source.add(consumer: consumer)
        consumer.onFrame = { receivedFrame in
            XCTAssertEqual(receivedFrame.metadata.frameIndex, 0)
            guard let pixelBuffer = receivedFrame.pixelBuffer else {
                XCTFail("Expected pixel buffer")
                return
            }
            XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 16)
            completion.fulfill()
        }

        source.start()

        wait(for: [completion], timeout: 2)
    }

    func testMediaProcessorNodeForwardsProcessedFrameToAttachedConsumer() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 5))
        let outputConsumer = TestConsumerNode()
        let processorNode = MediaProcessorNode(processors: [
            ClosureFrameProcessor { frame, completion in
                var output = frame
                output.metadata.frameIndex = 9
                completion(.success(output))
            }
        ])
        let completion = expectation(description: "processor node forwards output")

        outputConsumer.onFrame = { frame in
            XCTAssertEqual(frame.metadata.frameIndex, 9)
            completion.fulfill()
        }
        processorNode.add(consumer: outputConsumer)

        processorNode.consume(input, from: processorNode) { result in
            if case .failure = result {
                XCTFail("Unexpected processor node failure")
            }
        }

        wait(for: [completion], timeout: 1)
    }

    func testMediaGraphRoutesFramesToMultipleBranches() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let source = TestSource(frames: [input])
        let firstSink = TestSink()
        let secondSink = TestSink()
        let firstBranch = MediaGraphBranch(
            processors: [
                ClosureFrameProcessor { frame, completion in
                    var output = frame
                    output.metadata.frameIndex = 11
                    completion(.success(output))
                }
            ],
            sinks: [firstSink]
        )
        let secondBranch = MediaGraphBranch(
            processors: [
                ClosureFrameProcessor { frame, completion in
                    var output = frame
                    output.metadata.frameIndex = 21
                    completion(.success(output))
                }
            ],
            sinks: [secondSink]
        )
        let graph = MediaGraph(source: source, branches: [firstBranch, secondBranch])

        graph.start()

        XCTAssertEqual(firstSink.frames.first?.metadata.frameIndex, 11)
        XCTAssertEqual(secondSink.frames.first?.metadata.frameIndex, 21)
    }

    func testMediaGraphNestedBranchPropagatesFrameToChildSink() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let source = TestSource(frames: [input])
        let parentSink = TestSink()
        let childSink = TestSink()
        let childBranch = MediaGraphBranch(
            processors: [
                ClosureFrameProcessor { frame, completion in
                    var output = frame
                    output.metadata.frameIndex = 31
                    completion(.success(output))
                }
            ],
            sinks: [childSink]
        )
        let parentBranch = MediaGraphBranch(
            processors: [
                ClosureFrameProcessor { frame, completion in
                    var output = frame
                    output.metadata.frameIndex = 30
                    completion(.success(output))
                }
            ],
            sinks: [parentSink],
            children: [childBranch]
        )
        let graph = MediaGraph(source: source, branches: [parentBranch])

        graph.start()

        XCTAssertEqual(parentSink.frames.first?.metadata.frameIndex, 30)
        XCTAssertEqual(childSink.frames.first?.metadata.frameIndex, 31)
    }

    func testImageSourceEmitsFrameSequenceWithMetadata() throws {
        let frames = [
            StillImageFrame(image: try makeImage(width: 10, height: 10), duration: CMTime(value: 1, timescale: 30)),
            StillImageFrame(image: try makeImage(width: 20, height: 12), duration: CMTime(value: 2, timescale: 30))
        ]
        let source = ImageSource(frames: frames, renderSize: CGSize(width: 40, height: 24), callbackQueue: .main)
        let sink = TestSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])
        let completion = expectation(description: "image source finished")

        pipeline.completionHandler = {
            completion.fulfill()
        }

        pipeline.start()

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(sink.frames.count, 2)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(sink.frames.first?.pixelBuffer)), 40)
        XCTAssertEqual(CVPixelBufferGetHeight(try XCTUnwrap(sink.frames.first?.pixelBuffer)), 24)
        XCTAssertEqual(sink.frames.first?.metadata.presentationTime, .zero)
        XCTAssertEqual(sink.frames.last?.metadata.presentationTime, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(sink.frames.last?.metadata.duration, CMTime(value: 2, timescale: 30))
    }

    func testTimelineCompositionCompilesEmptyComposition() {
        let timeline = TimelineComposition(renderSize: CGSize(width: 1920, height: 1080), frameDuration: CMTime(value: 1, timescale: 30))

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.videoComposition.renderSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(compiled.videoComposition.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(compiled.composition.tracks.count, 0)
        XCTAssertEqual(compiled.audioMix.inputParameters.count, 0)
        XCTAssertEqual(compiled.renderInstructions.count, 0)
    }

    func testTimelineCompositionFlattensGroupLayerIntoResolvedLayers() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let child = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let group = GroupLayer(
            timeRange: CMTimeRange(start: CMTime(value: 60, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            layers: [child],
            layerLevel: 3
        )
        let timeline = TimelineComposition(layers: [group])

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.resolvedLayers.videoLayers.count, 1)
        XCTAssertEqual(compiled.resolvedLayers.videoLayers.first?.timeRange.start, CMTime(value: 60, timescale: 30))
        XCTAssertEqual(compiled.resolvedLayers.videoLayers.first?.layerLevel, 3)
    }

    func testTimelineCompositionGroupLayerAppliesInheritedOpacityTransformAndKeyframes() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let child = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        child.opacity = 0.8

        let group = GroupLayer(
            timeRange: CMTimeRange(start: CMTime(value: 60, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            layers: [child],
            layerLevel: 2
        )
        group.opacity = 0.5
        group.transform = CGAffineTransform(translationX: 24, y: 12)
        group.keyframes = [
            KeyframeAnimation(
                keyPath: "translation.y",
                values: [30, 0],
                keyTimes: [group.timeRange.start, group.timeRange.end]
            )
        ]

        let timeline = TimelineComposition(layers: [group])
        let compiled = timeline.compile()
        let state = try XCTUnwrap(compiled.renderInstructions.first?.layerStates.first)

        XCTAssertEqual(state.kind, .clip)
        XCTAssertEqual(state.layerLevel, 2)
        XCTAssertEqual(state.opacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(state.transform.tx, 24, accuracy: 0.0001)
        XCTAssertEqual(state.transform.ty, 30, accuracy: 0.0001)
        XCTAssertNotNil(state.trackID)
    }

    func testTimelineCompositionReusesSingleVideoTrackForNonOverlappingClips() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let first = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let second = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: CMTime(value: 30, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: CMTime(value: 30, timescale: 30), duration: CMTime(value: 30, timescale: 30))
        )
        let timeline = TimelineComposition(layers: [first, second])

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.composition.tracks(withMediaType: .video).count, 1)
        XCTAssertEqual(compiled.renderInstructions.count, 2)
        XCTAssertEqual(compiled.renderInstructions.map(\.sourceTrackIDs.count), [1, 1])
    }

    func testTimelineCompositionPreservesLayerOrderForOverlappingClips() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let background = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            layerLevel: 0
        )
        let foreground = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 1
        )
        let timeline = TimelineComposition(layers: [background, foreground])

        let compiled = timeline.compile()
        let overlapInstruction = try XCTUnwrap(compiled.renderInstructions.first(where: { $0.sourceTrackIDs.count == 2 }))

        XCTAssertEqual(overlapInstruction.layerLevels, [0, 1])
        XCTAssertEqual(overlapInstruction.sourceTrackIDs.count, 2)
        XCTAssertNotEqual(overlapInstruction.sourceTrackIDs[0], overlapInstruction.sourceTrackIDs[1])
    }

    func testTimelineCompositionBuildsCrossDissolveOpacityRamps() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let first = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            layerLevel: 0
        )
        let second = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: CMTime(value: 90, timescale: 30), duration: CMTime(value: 120, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            layerLevel: 1
        )
        let transitionRange = CMTimeRange(start: CMTime(value: 90, timescale: 30), duration: CMTime(value: 30, timescale: 30))
        let timeline = TimelineComposition(
            layers: [first, second],
            transitions: [Transition(timeRange: transitionRange, sourceLayerLevel: 0, destinationLayerLevel: 1)]
        )

        let compiled = timeline.compile()
        let transitionInstruction = try XCTUnwrap(
            compiled.videoComposition.instructions
                .compactMap { $0 as? AVMutableVideoCompositionInstruction }
                .first(where: { $0.timeRange == transitionRange })
        )
        XCTAssertEqual(transitionInstruction.layerInstructions.count, 2)

        var foundSourceRamp = false
        var foundDestinationRamp = false

        for instruction in transitionInstruction.layerInstructions {
            guard let layerInstruction = instruction as? AVMutableVideoCompositionLayerInstruction else { continue }
            var startOpacity: Float = 0
            var endOpacity: Float = 0
            var rampRange = CMTimeRange.invalid
            if layerInstruction.getOpacityRamp(
                for: transitionRange.start,
                startOpacity: &startOpacity,
                endOpacity: &endOpacity,
                timeRange: &rampRange
            ) {
                XCTAssertEqual(rampRange, transitionRange)
                if startOpacity == 1, endOpacity == 0 {
                    foundSourceRamp = true
                }
                if startOpacity == 0, endOpacity == 1 {
                    foundDestinationRamp = true
                }
            }
        }

        XCTAssertTrue(foundSourceRamp)
        XCTAssertTrue(foundDestinationRamp)
    }

    func testTimelineCompositionBuildsCrossDissolveAudioRamps() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let first = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            layerLevel: 0,
            volume: 0.8
        )
        let second = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: CMTime(value: 90, timescale: 30), duration: CMTime(value: 120, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 120, timescale: 30)),
            layerLevel: 1,
            volume: 0.6
        )
        let transitionRange = CMTimeRange(start: CMTime(value: 90, timescale: 30), duration: CMTime(value: 30, timescale: 30))
        let timeline = TimelineComposition(
            layers: [first, second],
            transitions: [Transition(timeRange: transitionRange, sourceLayerLevel: 0, destinationLayerLevel: 1)]
        )

        let compiled = timeline.compile()
        XCTAssertEqual(compiled.audioMix.inputParameters.count, 2)

        var foundFadeOut = false
        var foundFadeIn = false

        for parameter in compiled.audioMix.inputParameters {
            var startVolume: Float = 0
            var endVolume: Float = 0
            var rampRange = CMTimeRange.invalid
            if parameter.getVolumeRamp(
                for: transitionRange.start,
                startVolume: &startVolume,
                endVolume: &endVolume,
                timeRange: &rampRange
            ) {
                XCTAssertEqual(rampRange, transitionRange)
                if startVolume == 0.8, endVolume == 0 {
                    foundFadeOut = true
                }
                if startVolume == 0, endVolume == 0.6 {
                    foundFadeIn = true
                }
            }
        }

        XCTAssertTrue(foundFadeOut)
        XCTAssertTrue(foundFadeIn)
    }

    func testTimelineCompositionAppliesBaseAudioVolumeAndRampToAudioLayer() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let rampRange = CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 30, timescale: 30))
        let audioLayer = AudioLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            volume: 0.5,
            audioRamps: [
                AudioVolumeRamp(startVolume: 0.2, endVolume: 1.0, timeRange: rampRange)
            ]
        )
        let timeline = TimelineComposition(layers: [audioLayer])

        let compiled = timeline.compile()
        let parameter = try XCTUnwrap(compiled.audioMix.inputParameters.first)
        var startVolume: Float = 0
        var endVolume: Float = 0
        var resolvedRange = CMTimeRange.invalid

        XCTAssertTrue(
            parameter.getVolumeRamp(
                for: rampRange.start,
                startVolume: &startVolume,
                endVolume: &endVolume,
                timeRange: &resolvedRange
            )
        )
        XCTAssertEqual(resolvedRange, rampRange)
        XCTAssertEqual(startVolume, 0.1, accuracy: 0.0001)
        XCTAssertEqual(endVolume, 0.5, accuracy: 0.0001)
    }

    func testKeyframeAnimationAppliesEaseInOutInterpolation() throws {
        let animation = KeyframeAnimation(
            keyPath: "opacity",
            values: [0, 1],
            keyTimes: [.zero, CMTime(value: 10, timescale: 10)],
            easing: .easeInOut
        )

        let quarterPoint = try XCTUnwrap(animation.value(at: CMTime(value: 25, timescale: 100)))
        let lookupValue = try XCTUnwrap(
            KeyframeAnimation.value(for: "opacity", at: CMTime(value: 25, timescale: 100), animations: [animation])
        )

        XCTAssertEqual(quarterPoint, 0.125, accuracy: 0.0001)
        XCTAssertEqual(lookupValue, 0.125, accuracy: 0.0001)
    }

    func testKeyframeAnimationSupportsPerSegmentTimingFunctions() throws {
        let animation = KeyframeAnimation(
            keyPath: "opacity",
            values: [0, 1, 0.5],
            keyTimes: [
                .zero,
                CMTime(value: 10, timescale: 10),
                CMTime(value: 20, timescale: 10)
            ],
            timingFunctions: [.cubicEaseOut, .bounceEaseOut]
        )

        let firstSegment = try XCTUnwrap(animation.value(at: CMTime(value: 5, timescale: 10)))
        let secondSegment = try XCTUnwrap(animation.value(at: CMTime(value: 15, timescale: 10)))

        XCTAssertGreaterThan(firstSegment, 0.5)
        XCTAssertLessThan(secondSegment, 1.0)
        XCTAssertGreaterThan(secondSegment, 0.5)
    }

    func testTimelineCompositionCompilesKeyframedOpacityRamp() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30))
        )
        clip.keyframes = [
            KeyframeAnimation(
                keyPath: "opacity",
                values: [0.2, 0.9],
                keyTimes: [.zero, CMTime(value: 60, timescale: 30)],
                easing: .linear
            )
        ]
        let timeline = TimelineComposition(layers: [clip])

        let compiled = timeline.compile()
        let instruction = try XCTUnwrap(
            compiled.videoComposition.instructions
                .compactMap { $0 as? AVMutableVideoCompositionInstruction }
                .first
        )
        let layerInstruction = try XCTUnwrap(instruction.layerInstructions.first as? AVMutableVideoCompositionLayerInstruction)
        var startOpacity: Float = 0
        var endOpacity: Float = 0
        var rampRange = CMTimeRange.invalid

        XCTAssertTrue(
            layerInstruction.getOpacityRamp(
                for: .zero,
                startOpacity: &startOpacity,
                endOpacity: &endOpacity,
                timeRange: &rampRange
            )
        )
        XCTAssertEqual(startOpacity, 0.2, accuracy: 0.0001)
        XCTAssertEqual(endOpacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(rampRange, instruction.timeRange)
    }

    func testTimelineCompositionCompilesKeyframedTransformRamp() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30))
        )
        clip.keyframes = [
            KeyframeAnimation(
                keyPath: "translation.x",
                values: [0, 120],
                keyTimes: [.zero, CMTime(value: 60, timescale: 30)]
            ),
            KeyframeAnimation(
                keyPath: "scale",
                values: [1, 0.5],
                keyTimes: [.zero, CMTime(value: 60, timescale: 30)]
            )
        ]
        let timeline = TimelineComposition(layers: [clip])

        let compiled = timeline.compile()
        let instruction = try XCTUnwrap(
            compiled.videoComposition.instructions
                .compactMap { $0 as? AVMutableVideoCompositionInstruction }
                .first
        )
        let layerInstruction = try XCTUnwrap(instruction.layerInstructions.first as? AVMutableVideoCompositionLayerInstruction)
        var startTransform = CGAffineTransform.identity
        var endTransform = CGAffineTransform.identity
        var rampRange = CMTimeRange.invalid

        XCTAssertTrue(
            layerInstruction.getTransformRamp(
                for: .zero,
                start: &startTransform,
                end: &endTransform,
                timeRange: &rampRange
            )
        )
        XCTAssertEqual(startTransform.tx, 0, accuracy: 0.0001)
        XCTAssertEqual(endTransform.tx, 120, accuracy: 0.0001)
        XCTAssertEqual(startTransform.a, 1, accuracy: 0.0001)
        XCTAssertEqual(endTransform.a, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rampRange, instruction.timeRange)
    }

    func testTimelineCompositionExposesEffectIntensityStateInRenderInstructions() {
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            intensity: 0.4,
            layerLevel: 3
        )
        effect.keyframes = [
            KeyframeAnimation(
                keyPath: "effect.intensity",
                values: [0.4, 1.0],
                keyTimes: [.zero, CMTime(value: 60, timescale: 30)]
            )
        ]
        let timeline = TimelineComposition(layers: [effect])

        let compiled = timeline.compile()
        guard let state = compiled.renderInstructions.first?.layerStates.first else {
            return XCTFail("Missing effect state")
        }
        guard let intensity = state.effectIntensity else {
            return XCTFail("Missing effect intensity")
        }

        XCTAssertEqual(state.layerLevel, 3)
        XCTAssertEqual(intensity, 0.4, accuracy: 0.0001)
    }

    func testTimelineCompositionIncludesImageAndEffectLayersInRenderPlan() throws {
        let imageLayer = ImageLayer(
            image: try makeImage(width: 20, height: 10),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 45, timescale: 30)),
            layerLevel: 1
        )
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 45, timescale: 30)),
            processor: PassthroughFrameProcessor(),
            intensity: 0.6,
            layerLevel: 2
        )
        let timeline = TimelineComposition(layers: [imageLayer, effect])

        let compiled = timeline.compile()
        let instruction = try XCTUnwrap(compiled.renderInstructions.first)
        let imageState = try XCTUnwrap(instruction.layerStates.first(where: { $0.kind == .image }))
        let effectState = try XCTUnwrap(instruction.layerStates.first(where: { $0.kind == .effect }))
        let intensity = try XCTUnwrap(effectState.effectIntensity)

        XCTAssertEqual(instruction.processors.count, 1)
        XCTAssertEqual(imageState.image?.width, 20)
        XCTAssertEqual(imageState.image?.height, 10)
        XCTAssertNil(imageState.trackID)
        XCTAssertNotNil(effectState.processor)
        XCTAssertEqual(intensity, 0.6, accuracy: 0.0001)
    }

    func testTimelineCompositionBuildsRenderPlanWithSourceDescriptors() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            source: AssetClipSource(
                asset: asset,
                sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30))
            ),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            layerLevel: 0
        )
        let image = ImageLayer(
            source: StillImageSource(image: try makeImage(width: 32, height: 18)),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            layerLevel: 1
        )
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)),
            source: EffectSource(processor: PassthroughFrameProcessor(), intensity: 0.75),
            layerLevel: 2
        )
        let timeline = TimelineComposition(layers: [clip, image, effect])

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.renderPlan.assetSegments.count, 1)
        XCTAssertEqual(compiled.renderPlan.imageSegments.count, 1)
        XCTAssertEqual(compiled.renderPlan.processorSegments.count, 1)
        XCTAssertEqual(compiled.renderPlan.visualIntervals.count, 1)
        XCTAssertEqual(compiled.renderPlan.assetSegments.first?.compositionTrackID, compiled.renderInstructions.first?.sourceTrackIDs.first)
        XCTAssertEqual(compiled.renderPlan.imageSegments.first?.source.naturalSize.width, 32)
        XCTAssertEqual(
            Double(compiled.renderPlan.processorSegments.first?.intensity(at: .zero) ?? 0),
            0.75,
            accuracy: 0.0001
        )
    }

    func testTimelineCompositionIncludesTextLayersInOverlayAndRenderPlan() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 45, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 45, timescale: 30)),
            layerLevel: 0
        )
        let text = TextLayer(
            attributedText: NSAttributedString(string: "Kakapos"),
            frame: CGRect(x: 24, y: 36, width: 180, height: 48),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 45, timescale: 30)),
            layerLevel: 2,
            animationStyle: .opacity
        )
        let timeline = TimelineComposition(layers: [clip, text])

        let compiled = timeline.compile()
        let firstInstruction = try XCTUnwrap(compiled.renderInstructions.first)
        let textState = try XCTUnwrap(firstInstruction.layerStates.first(where: { $0.kind == .text }))

        XCTAssertEqual(compiled.resolvedLayers.textLayers.count, 1)
        XCTAssertEqual(compiled.renderPlan.textSegments.count, 1)
        XCTAssertEqual(compiled.renderPlan.visualIntervals.first?.textSegments.count, 1)
        XCTAssertNotNil(compiled.overlayLayer)
        XCTAssertNotNil(compiled.videoComposition.animationTool)
        XCTAssertNil(textState.trackID)
        XCTAssertEqual(textState.layerLevel, 2)
    }

    func testCompiledTimelineCompositionBuildsImageSourceAndProcessorChain() throws {
        let image = ImageLayer(
            source: StillImageSource(image: try makeImage(width: 24, height: 24)),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 0
        )
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            source: EffectSource(processor: PassthroughFrameProcessor(), intensity: 1),
            layerLevel: 1
        )
        let timeline = TimelineComposition(layers: [image, effect])
        let compiled = timeline.compile()

        let imageSource = try XCTUnwrap(compiled.makeImageSource())
        let chain = compiled.makeProcessorChain()
        let sink = TestSink()
        chain.sinks = [sink]
        let pipeline = MediaPipeline(source: imageSource, processors: chain.processors, sinks: chain.sinks)
        let completion = expectation(description: "compiled image source pipeline finishes")

        pipeline.completionHandler = {
            completion.fulfill()
        }

        pipeline.start()

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(sink.frames.count, 1)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(sink.frames.first?.pixelBuffer)), 720)
        XCTAssertEqual(CVPixelBufferGetHeight(try XCTUnwrap(sink.frames.first?.pixelBuffer)), 1280)
        XCTAssertEqual(chain.processors.count, 1)
    }

    func testReaderWriterProgressInfoUsesVideoProgressWhenAudioTrackIsMissing() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.65,
            audioProgress: 0.1,
            hasVideo: true,
            hasAudio: false
        )

        XCTAssertEqual(info.fractionCompleted, 0.65, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoAveragesEnabledTracksAndClampsValues() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 1.2,
            audioProgress: -0.2,
            hasVideo: true,
            hasAudio: true
        )

        XCTAssertEqual(info.videoProgress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(info.audioProgress, 0.0, accuracy: 0.0001)
        XCTAssertEqual(info.fractionCompleted, 0.5, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoReturnsZeroWithoutActiveTracksAndUsesFinishWritingForOverallProgress() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.9,
            audioProgress: 0.6,
            hasVideo: false,
            hasAudio: false,
            finishWritingProgress: 0.4
        )

        XCTAssertEqual(info.fractionCompleted, 0.0, accuracy: 0.0001)
        XCTAssertEqual(info.overallFractionCompleted, 0.4, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoKeepsOverallProgressBelowOneBeforeFinishWriting() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 1.0,
            audioProgress: 1.0,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.0
        )

        XCTAssertEqual(info.fractionCompleted, 1.0, accuracy: 0.0001)
        XCTAssertEqual(info.overallFractionCompleted, 0.95, accuracy: 0.0001)
    }

    func testReaderWriterExportJobKeepsStableStatusOutsideExportingState() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let expectation = expectation(description: "cancel status callback")
        var receivedStatuses: [ReaderWriterExportJob.Status] = []
        job.statusHandler = { status in
            receivedStatuses.append(status)
            if status == .cancelled {
                expectation.fulfill()
            }
        }

        job.pause()
        XCTAssertEqual(job.status, .idle)

        job.resume()
        XCTAssertEqual(job.status, .idle)

        job.cancel()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(receivedStatuses, [.cancelled])

        job.resume()
        XCTAssertEqual(job.status, .cancelled)
    }

    func testReaderWriterExportJobPauseAndResumeTransitionFromExportingState() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        job._setStatusForTesting(.exporting)

        job.pause()
        XCTAssertEqual(job.status, .paused)

        job.resume()
        XCTAssertEqual(job.status, .exporting)
    }

    func testReaderWriterExportJobRepeatedCancelDoesNotNotifyTwice() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let expectation = expectation(description: "cancel callback")
        expectation.expectedFulfillmentCount = 1
        var statuses: [ReaderWriterExportJob.Status] = []
        job.statusHandler = { status in
            statuses.append(status)
            if status == .cancelled {
                expectation.fulfill()
            }
        }

        job.cancel()
        job.cancel()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(statuses, [.cancelled])
    }

    func testVideoXExportPipelineDefaultsToAssetExportSession() {
        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: [:]), .assetExportSession)
    }

    func testVideoXExportPipelineCanSwitchToReaderWriter() {
        let options: [VideoX.Option: Any] = [
            .ExportPipeline: VideoX.ExportPipeline.readerWriter
        ]

        XCTAssertEqual(VideoX.Option.setupExportPipeline(options: options), .readerWriter)
    }

    func testVideoXMakeExportJobReturnsNilForAssetExportSessionPipeline() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportJob = try exporter.makeExportJob(
            options: [:],
            instructions: [instruction]
        )

        XCTAssertNil(exportJob)
    }

    func testVideoXMakeExportJobReturnsReaderWriterJobWhenConfigured() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())
        let outputURL = try XCTUnwrap(exporter.provider.outputURL as URL?)

        let exportJob = try exporter.makeExportJob(
            options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
            instructions: [instruction]
        )

        XCTAssertNotNil(exportJob)
        XCTAssertEqual(exportJob?.status, .idle)
        XCTAssertEqual(exportJob?._videoProcessorCountForTesting, 1)
        XCTAssertEqual(try exporter.makeReaderWriterExportJob(instructions: [instruction]).status, .idle)
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "mp4")
    }

    func testVideoXReaderWriterExportKeepsUnsupportedInstructionsInVideoComposition() throws {
        let exporter = try makeSampleExporter()
        let filter = FilterInstruction(processor: PassthroughFrameProcessor())
        let rotate = RotateInstruction(rotationAngle: .angle90)

        let exportJob = try XCTUnwrap(
            exporter.makeExportJob(
                options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
                instructions: [filter, rotate]
            )
        )

        XCTAssertEqual(exportJob._videoProcessorCountForTesting, 1)
    }

    func testReaderWriterExportJobInvokesFrameProcessorDuringExport() throws {
        let exporter = try makeSampleExporter()
        let callbackExpectation = expectation(description: "frame processor invoked")
        let exportExpectation = expectation(description: "reader writer export finished")
        callbackExpectation.assertForOverFulfill = false
        var invocationCount = 0

        let instruction = FilterInstruction(processor: ClosureFrameProcessor { frame, completion in
            invocationCount += 1
            callbackExpectation.fulfill()
            completion(.success(frame))
        })

        let exportJob = try XCTUnwrap(
            exporter.makeExportJob(
                options: [
                    .ExportPipeline: VideoX.ExportPipeline.readerWriter,
                    .ExportSessionTimeRange: TimeRangeType.range(0...0.2)
                ],
                instructions: [instruction]
            )
        )

        exportJob.export { result in
            switch result {
            case .success(let outputURL):
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            case .failure(let error):
                XCTFail("Unexpected reader/writer export failure: \(error)")
            }
            exportExpectation.fulfill()
        }

        wait(for: [callbackExpectation, exportExpectation], timeout: 15)
        XCTAssertGreaterThan(invocationCount, 0)
    }

    func testVideoXMakeExportTaskReturnsAssetSessionTaskByDefault() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportTask = try exporter.makeExportTask(
            options: [:],
            instructions: [instruction]
        )

        XCTAssertNotNil(exportTask.assetExportSession)
        XCTAssertNil(exportTask.readerWriterJob)
        XCTAssertFalse(exportTask.supportsPauseResume)
        XCTAssertEqual(exportTask.status, .idle)
    }

    func testVideoXMakeExportTaskReturnsReaderWriterTaskWhenConfigured() throws {
        let exporter = try makeSampleExporter()
        let instruction = FilterInstruction(processor: PassthroughFrameProcessor())

        let exportTask = try exporter.makeExportTask(
            options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
            instructions: [instruction]
        )

        XCTAssertNil(exportTask.assetExportSession)
        XCTAssertNotNil(exportTask.readerWriterJob)
        XCTAssertTrue(exportTask.supportsPauseResume)
        XCTAssertEqual(exportTask.status, .idle)

        exportTask.pause()
        XCTAssertEqual(exportTask.status, .idle)
        exportTask.cancel()
        XCTAssertEqual(exportTask.status, .cancelled)
    }

    func testVideoXExportTaskMapsReaderWriterStatuses() throws {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let task = VideoX.ExportTask(readerWriterJob: job)

        job._setStatusForTesting(.exporting)
        XCTAssertEqual(task.status, .exporting)
        job._setStatusForTesting(.paused)
        XCTAssertEqual(task.status, .paused)
        job._setStatusForTesting(.failed)
        XCTAssertEqual(task.status, .failed)
        job._setStatusForTesting(.completed)
        XCTAssertEqual(task.status, .completed)
    }

    func testPreviewSinkBuildsPreviewImageAndPreservesMetadata() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let metadata = FrameMetadata(
            presentationTime: CMTime(value: 5, timescale: 30),
            sourceTime: CMTime(value: 4, timescale: 30),
            frameIndex: 9
        )
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata)
        let expectation = self.expectation(description: "preview sink callback")
        var receivedImage: CGImage?
        var receivedMetadata: FrameMetadata?

        let sink = PreviewSink { image, previewMetadata in
            receivedImage = image
            receivedMetadata = previewMetadata
            expectation.fulfill()
        }

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedImage?.width, 12)
        XCTAssertEqual(receivedImage?.height, 10)
        XCTAssertEqual(receivedMetadata?.frameIndex, metadata.frameIndex)
        XCTAssertEqual(receivedMetadata?.presentationTime, metadata.presentationTime)
    }

    func testPreviewSinkCachesLatestFrameWhilePausedAndFlushesOnResume() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(pixelBuffer: firstBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let second = MediaFrame(pixelBuffer: secondBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30), frameIndex: 2))
        let expectation = expectation(description: "flush cached preview frame")
        expectation.expectedFulfillmentCount = 2
        var receivedFrameIndices: [Int64] = []

        let sink = PreviewSink { _, metadata in
            receivedFrameIndices.append(metadata.frameIndex ?? -1)
            expectation.fulfill()
        }

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        sink.pause()
        XCTAssertEqual(sink.state, PreviewSink.State.paused)

        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(sink.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(sink.lastImage?.width, 10)

        sink.resume()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedFrameIndices, [1, 2])
        XCTAssertEqual(sink.state, PreviewSink.State.active)
        XCTAssertEqual(sink.lastFrame?.metadata.frameIndex, 2)
        XCTAssertEqual(sink.lastImage?.width, 14)
    }

    func testMediaGraphAppendReconnectsNewBranchToSourceAdapter() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let source = TestSource(frames: [input])
        let firstSink = TestSink()
        let secondSink = TestSink()
        let graph = MediaGraph(source: source, branches: [
            MediaGraphBranch(
                processors: [
                    ClosureFrameProcessor { frame, completion in
                        var output = frame
                        output.metadata.frameIndex = 10
                        completion(.success(output))
                    }
                ],
                sinks: [firstSink]
            )
        ])

        graph.append(
            MediaGraphBranch(
                processors: [
                    ClosureFrameProcessor { frame, completion in
                        var output = frame
                        output.metadata.frameIndex = 20
                        completion(.success(output))
                    }
                ],
                sinks: [secondSink]
            )
        )

        graph.start()

        XCTAssertEqual(firstSink.frames.first?.metadata.frameIndex, 10)
        XCTAssertEqual(secondSink.frames.first?.metadata.frameIndex, 20)
    }

    func testMediaPipelineStopFinishesSinksOnlyOnceWhenSourceAlsoFinishes() {
        let source = StopAwareSource()
        let sink = CountingSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])
        let expectation = self.expectation(description: "completion called once")
        expectation.expectedFulfillmentCount = 1

        pipeline.completionHandler = {
            expectation.fulfill()
        }

        pipeline.stop()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(sink.finishCount, 1)
    }

    func testMediaProcessorChainCanBeNestedAsSink() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let expectation = expectation(description: "nested chain consumes processed frame")
        let sink = TestSink()

        let nestedChain = MediaProcessorChain(
            processors: [
                ClosureFrameProcessor { frame, completion in
                    var output = frame
                    output.metadata.frameIndex = 3
                    completion(.success(output))
                }
            ],
            sinks: [sink]
        )

        nestedChain.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected nested chain failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(sink.frames.first?.metadata.frameIndex, 3)
    }

    func testMediaPipelinePauseResumeAndCancelPropagateToSinks() {
        let source = TestSource(frames: [])
        let sink = LifecycleAwareSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])

        pipeline.pause()
        pipeline.resume()
        pipeline.cancel()

        XCTAssertEqual(sink.pauseCount, 1)
        XCTAssertEqual(sink.resumeCount, 1)
        XCTAssertEqual(sink.cancelCount, 1)
    }

    func testPlayerFrameCoordinatorResetsFrameIndexWhenCurrentItemChanges() {
        final class Token: NSObject {}

        var coordinator = PlayerFrameCoordinator()
        let first = Token()
        let second = Token()

        XCTAssertTrue(coordinator.start(with: first))
        XCTAssertEqual(coordinator.generation, 1)
        XCTAssertEqual(coordinator.playbackState, .running)
        XCTAssertEqual(coordinator.markFrameOutput(), 1)
        XCTAssertEqual(coordinator.markFrameOutput(), 2)

        XCTAssertTrue(coordinator.updateCurrentItem(second))
        XCTAssertEqual(coordinator.frameIndex, 0)
        XCTAssertEqual(coordinator.generation, 2)
        XCTAssertEqual(coordinator.markFrameOutput(), 1)
    }

    func testPlayerFrameCoordinatorWaitsForMediaDataAndRecovers() {
        final class Token: NSObject {}

        var coordinator = PlayerFrameCoordinator()
        _ = coordinator.start(with: Token())

        XCTAssertTrue(coordinator.beginWaitingForMediaData())
        XCTAssertEqual(coordinator.playbackState, .waitingForMediaData)
        XCTAssertFalse(coordinator.shouldDriveDisplayLink)

        XCTAssertTrue(coordinator.mediaDataWillChange())
        XCTAssertEqual(coordinator.playbackState, .running)
        XCTAssertTrue(coordinator.shouldDriveDisplayLink)
    }

    func testPlayerFrameCoordinatorPauseResumeAndStopTransitions() {
        final class Token: NSObject {}

        var coordinator = PlayerFrameCoordinator()
        _ = coordinator.start(with: Token())

        coordinator.pause()
        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertFalse(coordinator.shouldDriveDisplayLink)

        coordinator.resume()
        XCTAssertEqual(coordinator.playbackState, .running)
        XCTAssertTrue(coordinator.shouldDriveDisplayLink)

        coordinator.stop()
        XCTAssertEqual(coordinator.playbackState, .finished)
        XCTAssertFalse(coordinator.shouldDriveDisplayLink)
    }

    #if canImport(UIKit)
    func testPlayerFrameSourceTracksPlaybackStateAndWaitingTransitions() {
        let player = AVPlayer()
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, _ in
                driver.configuration = configuration
                return driver
            }
        )
        var states: [PlayerFrameSource.State] = []
        source.stateChangedHandler = { states.append($0) }

        source.start()
        XCTAssertEqual(source.state, .active)

        driver.waitingForMediaDataHandler?(CMTime(value: 3, timescale: 30))
        XCTAssertEqual(source.state, .waitingForMediaData)

        driver.mediaDataWillChangeHandler?()
        XCTAssertEqual(source.state, .active)

        source.pause()
        XCTAssertEqual(source.state, .paused)

        source.resume()
        XCTAssertEqual(source.state, .active)

        source.stop()
        XCTAssertEqual(source.state, .finished)
        XCTAssertEqual(states, [.active, .waitingForMediaData, .active, .paused, .active, .finished])
    }

    func testPlayerFrameSourceRequestFrameUpdateAndRefreshForwardToDriver() {
        let player = AVPlayer()
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, _ in
                driver.configuration = configuration
                return driver
            }
        )

        source.start()
        source.requestFrameUpdate()
        source.refreshCurrentFrameIfNeeded()

        XCTAssertEqual(driver.setNeedsUpdateCallCount, 1)
        XCTAssertEqual(driver.updateIfNeededCallCount, 1)
    }

    func testPlayerFrameSourceCachesLastFrameAndMarksManualRefreshMetadata() throws {
        let player = AVPlayer()
        let driver = FakePlayerFrameDriver()
        let expectation = expectation(description: "player frame emitted")
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let pixelBuffer = try makePixelBuffer(width: 18, height: 12)
        var receivedFrame: MediaFrame?

        source.frameHandler = { frame in
            receivedFrame = frame
            expectation.fulfill()
        }

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 4, timescale: 30),
                playerTimestamp: CMTime(value: 4, timescale: 30),
                requestTimestamp: CMTime(value: 5, timescale: 30),
                pixelBuffer: pixelBuffer
            )
        )

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(source.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(source.lastFrame?.pixelBuffer)), 18)
        XCTAssertEqual(receivedFrame?.metadata.userInfo[PlayerFrameSource.MetadataKey.frameRequestReason] as? String, "manual")
    }

    func testPlayerFrameSourceSeekRecordsTargetAndRefreshesDriver() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let expectation = expectation(description: "seek completed")
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, _ in
                driver.configuration = configuration
                return driver
            }
        )
        let target = CMTime(value: 15, timescale: 30)

        source.start()
        source.seek(to: target) { finished in
            XCTAssertTrue(finished)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(source.lastSeekTargetTime, target)
        XCTAssertGreaterThanOrEqual(driver.setNeedsUpdateCallCount, 1)
        XCTAssertGreaterThanOrEqual(driver.updateIfNeededCallCount, 1)
        XCTAssertEqual(source.state, .active)
    }
    #endif

    func testRecorderSinkFinishRecordingReturnsRecordedClip() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero)
        )
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30))
        )
        let appendExpectation = self.expectation(description: "append frames")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = self.expectation(description: "finish recording")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .finished)
        XCTAssertEqual(recordedClip?.outputURL, outputURL)
        XCTAssertEqual(recordedClip?.startedAt, .zero)
        XCTAssertEqual(recordedClip?.endedAt, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 1, timescale: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testRecorderSinkPauseResumeRemovesPausedGapFromClipDuration() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 90, timescale: 30)))
        let appendExpectation = expectation(description: "append frames around pause")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = expectation(description: "finish paused recording")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        sink.pauseRecording(at: CMTime(value: 30, timescale: 30))
        XCTAssertEqual(sink.state, .paused)
        sink.resumeRecording()
        XCTAssertEqual(sink.state, .recording)

        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 30, timescale: 30))
        XCTAssertEqual(recordedClip?.segments.count, 2)
        XCTAssertEqual(recordedClip?.segments.first?.duration, CMTime(value: 30, timescale: 30))
    }

    func testRecorderSinkFinishWhilePausedKeepsRecordedDuration() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 30, timescale: 30))
        )
        let appendExpectation = expectation(description: "append paused clip frames")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = expectation(description: "finish paused clip")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.pauseRecording(at: CMTime(value: 60, timescale: 30))
        XCTAssertEqual(sink.state, .paused)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .finished)
        XCTAssertEqual(recordedClip?.startedAt, .zero)
        XCTAssertEqual(recordedClip?.endedAt, CMTime(value: 30, timescale: 30))
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 30, timescale: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testRecorderSinkPauseWithoutExplicitTimeDropsPausedFramesUntilResume() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 30, timescale: 30))
        )
        let pausedFrame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 60, timescale: 30))
        )
        let resumedFrame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 90, timescale: 30))
        )
        let appendExpectation = expectation(description: "append non-paused frames")
        appendExpectation.expectedFulfillmentCount = 4
        let finishExpectation = expectation(description: "finish resumed recording")
        var recordedClip: RecordedClip?
        var durations: [CMTime] = []

        sink.durationChangedHandler = { duration in
            durations.append(duration)
        }

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        sink.pauseRecording()
        XCTAssertEqual(sink.state, .paused)

        sink.consume(pausedFrame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        sink.resumeRecording()
        XCTAssertEqual(sink.state, .recording)

        sink.consume(resumedFrame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected resumed recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 601, timescale: 600))
        XCTAssertEqual(durations.last, CMTime(value: 601, timescale: 600))
        XCTAssertEqual(recordedClip?.segments.count, 2)
    }

    func testRecorderSinkCancelMakesFinishReturnExportCancelled() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let appendExpectation = expectation(description: "append first frame")
        let finishExpectation = expectation(description: "finish cancelled recording")
        var receivedError: Error?

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)
        sink.cancel()

        sink.finishRecording { result in
            if case .failure(let error) = result {
                receivedError = error
            } else {
                XCTFail("Expected cancelled finish to fail")
            }
            finishExpectation.fulfill()
        }

        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .cancelled)
        XCTAssertNil(sink.recordedClip)
        guard let error = receivedError as? VideoX.Error else {
            return XCTFail("Expected VideoX.Error.exportCancelled")
        }
        if case .exportCancelled = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected VideoX.Error.exportCancelled")
        }
    }

    func testCameraSessionLifecycleTracksStartInterruptionResumeAndStop() {
        var lifecycle = CameraSessionLifecycle(position: .back)

        XCTAssertEqual(lifecycle.handle(.startRequested), .willStart)
        XCTAssertEqual(lifecycle.state, .starting)
        XCTAssertEqual(lifecycle.handle(.didStartRunning), .didStart)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.handle(.wasInterrupted), .wasInterrupted)
        XCTAssertEqual(lifecycle.state, .interrupted)
        XCTAssertEqual(lifecycle.handle(.interruptionEnded), .interruptionEnded)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.handle(.didStopRunning), .didStop)
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testCameraSessionLifecycleTracksCameraPositionChanges() {
        var lifecycle = CameraSessionLifecycle(position: .back)

        XCTAssertEqual(lifecycle.handle(.positionChanged(.front)), .positionChanged(.front))
        XCTAssertEqual(lifecycle.position, .front)
    }

    func testCameraSessionLifecycleTracksRecoverableRuntimeErrors() {
        var lifecycle = CameraSessionLifecycle(position: .back)
        _ = lifecycle.handle(.startRequested)
        _ = lifecycle.handle(.didStartRunning)

        XCTAssertEqual(
            lifecycle.handle(.runtimeError(isRecoverable: true, description: "reset")),
            .runtimeError(isRecoverable: true, description: "reset")
        )
        XCTAssertEqual(lifecycle.state, .error)
        XCTAssertTrue(lifecycle.shouldAttemptRecovery)
    }

    func testCameraSessionLifecycleTracksNonRecoverableRuntimeErrorsWithoutRecovery() {
        var lifecycle = CameraSessionLifecycle(position: .back)
        _ = lifecycle.handle(.startRequested)
        _ = lifecycle.handle(.didStartRunning)

        XCTAssertEqual(
            lifecycle.handle(.runtimeError(isRecoverable: false, description: "fatal")),
            .runtimeError(isRecoverable: false, description: "fatal")
        )
        XCTAssertEqual(lifecycle.state, .error)
        XCTAssertFalse(lifecycle.shouldAttemptRecovery)

        XCTAssertEqual(lifecycle.handle(.startRequested), .willStart)
        XCTAssertEqual(lifecycle.handle(.didStartRunning), .didStart)
        XCTAssertEqual(lifecycle.state, .running)
    }
}

private final class TestSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private let frames: [MediaFrame]

    init(frames: [MediaFrame]) {
        self.frames = frames
    }

    func start() {
        frames.forEach { delegate?.mediaSource(self, didOutput: $0) }
        delegate?.mediaSourceDidFinish(self)
    }

    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}

private final class TestSink: MediaSink {
    var frames: [MediaFrame] = []

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        frames.append(frame)
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

private final class StopAwareSource: MediaSource {
    weak var delegate: MediaSourceDelegate?

    func start() {}
    func pause() {}
    func resume() {}

    func stop() {
        delegate?.mediaSourceDidFinish(self)
    }

    func cancel() {}
}

private final class CountingSink: MediaSink {
    var finishCount = 0

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        finishCount += 1
        completion(.success(()))
    }
}

private final class LifecycleAwareSink: MediaSink {
    var pauseCount = 0
    var resumeCount = 0
    var cancelCount = 0

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func pause() {
        pauseCount += 1
    }

    func resume() {
        resumeCount += 1
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class TestConsumerNode: MediaFrameConsumerNode {
    var onFrame: ((MediaFrame) -> Void)?

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        onFrame?(frame)
        completion(.success(()))
    }
}

#if canImport(UIKit)
private final class FakePlayerFrameDriver: PlayerFrameDriving {
    var configuration: PlayerFrameOutputDriver.Configuration = .default
    var waitingForMediaDataHandler: ((CMTime) -> Void)?
    var mediaDataWillChangeHandler: (() -> Void)?
    var frameHandler: ((PlayerFrameOutputDriver.VideoFrame) -> Void)?
    private(set) var setNeedsUpdateCallCount = 0
    private(set) var updateIfNeededCallCount = 0

    func setNeedsUpdate() {
        setNeedsUpdateCallCount += 1
    }

    func updateIfNeeded() {
        updateIfNeededCallCount += 1
    }

    func emitFrame(_ frame: PlayerFrameOutputDriver.VideoFrame) {
        frameHandler?(frame)
    }
}
#endif

private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    XCTAssertEqual(status, kCVReturnSuccess)
    return pixelBuffer!
}

private func makeImage(width: Int, height: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(domain: "MediaEngineTests", code: -1)
    }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        throw NSError(domain: "MediaEngineTests", code: -2)
    }
    return image
}

private func makeSampleExporter() throws -> VideoX {
    let sampleURL = try makeSampleAssetURL()
    XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")
    return VideoX(provider: .init(with: sampleURL, to: outputURL))
}

private func makeSampleAssetURL() throws -> URL {
    let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("KakaposExamples")
        .appendingPathComponent("IMG_1388.mp4")
    XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    return sampleURL
}
