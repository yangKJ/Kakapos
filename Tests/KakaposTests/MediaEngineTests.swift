import XCTest
import AVFoundation
import CoreGraphics
@testable import Kakapos

final class MediaEngineTests: XCTestCase {

    func testEngineCatalogDefinesPublicEnginesAndSharedMediaCore() throws {
        let engines = KakaposEngineCatalog.engines
        let publicEngines = KakaposEngineCatalog.publicEngines

        XCTAssertEqual(engines.map(\.engine), [.mediaCore, .video, .camera, .timeline])
        XCTAssertEqual(publicEngines.map(\.engine), [.video, .camera, .timeline])
        XCTAssertEqual(KakaposSurface.engines.map(\.engine), engines.map(\.engine))
        XCTAssertEqual(KakaposSurface.publicEngines.map(\.engine), publicEngines.map(\.engine))

        let core = try XCTUnwrap(KakaposSurface.engine(named: "mediaCore"))
        XCTAssertEqual(core.displayName, "Media Core")
        XCTAssertEqual(core.primaryTypes, ["FrameProcessor", "MediaFrame", "FrameMetadata", "MediaSource", "MediaSink", "MediaPipeline", "MediaProcessorChain"])
        XCTAssertTrue(core.boundary.contains("Foundation layer only"))

        let video = try XCTUnwrap(KakaposSurface.engine(named: "video"))
        XCTAssertEqual(video.displayName, "Video Engine")
        XCTAssertEqual(video.boards, [.export, .preview])
        XCTAssertTrue(video.primaryTypes.contains("Instruction"))
        XCTAssertTrue(video.primaryTypes.contains("FilterInstruction"))
        XCTAssertTrue(video.boundary.contains("Export instructions belong here"))

        let camera = try XCTUnwrap(KakaposSurface.engine(named: "camera"))
        XCTAssertEqual(camera.boards, [.preview, .record])
        XCTAssertTrue(camera.primaryTypes.contains("CameraSource"))
        XCTAssertTrue(camera.primaryTypes.contains("RecordingPipeline"))

        let timeline = try XCTUnwrap(KakaposSurface.engine(named: "timeline"))
        XCTAssertEqual(timeline.boards, [.timeline])
        XCTAssertTrue(timeline.primaryTypes.contains("TimelineComposition"))
        XCTAssertTrue(timeline.boundary.contains("processor plans"))
    }

    func testEngineCatalogIsCodableForExternalInspection() throws {
        let data = try JSONEncoder().encode(KakaposEngineCatalog.engines)
        let decoded = try JSONDecoder().decode([KakaposEngineInfo].self, from: data)

        XCTAssertEqual(decoded.map(\.id), ["mediaCore", "video", "camera", "timeline"])
        XCTAssertEqual(decoded.first(where: { $0.engine == .video })?.boardNames, ["Export", "Preview"])
        XCTAssertEqual(decoded.first(where: { $0.engine == .camera })?.boardNames, ["Preview", "Record"])
        XCTAssertEqual(decoded.first(where: { $0.engine == .timeline })?.boardNames, ["Timeline"])
    }

    func testCapabilityCatalogGroupsPublicSurfaceIntoFourBoards() {
        let boards = KakaposCapabilityCatalog.boards
        let starterBoards = KakaposCapabilityCatalog.starterBoards
        let guide = KakaposCapabilityCatalog.guide

        XCTAssertEqual(boards.count, 4)
        XCTAssertEqual(starterBoards.map(\.board), boards.map(\.board))
        XCTAssertEqual(boards.map(\.board), [.export, .preview, .record, .timeline])
        XCTAssertEqual(guide.boardCount, 4)
        XCTAssertEqual(guide.boardNames, ["Export", "Preview", "Record", "Timeline"])
        XCTAssertEqual(guide.starterBoardNames, ["Export", "Preview", "Record", "Timeline"])
        XCTAssertEqual(guide.summaryText, "Kakapos keeps adoption lightweight with 4 boards: Export · Preview · Record · Timeline.")
        XCTAssertEqual(guide.starterText, "Start from Export · Preview · Record · Timeline when you only need the narrow read-only entry layer.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "export")?.displayName, "Export")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "preview")?.primaryTypes, ["PreviewPipeline", "PlayerFrameSource", "PreviewSink", "MediaPipeline", "MediaProcessorChain"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "record")?.primaryTypes, ["CameraEngine", "RecordingPipeline", "CameraSource", "CameraDeviceController", "CameraPreviewController", "CameraRecordingController", "RecorderSink", "RecordingSession", "CameraAdvancedOutput"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "timeline")?.primaryTypes, ["TimelinePipeline", "TimelineExportTask", "TimelineComposition", "ClipLayer", "ImageLayer", "AudioLayer", "EffectLayer", "GroupLayer", "Transition", "KeyframeAnimation"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "export")?.starterTypes, ["VideoX", "ReaderWriterExportJob"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "preview")?.starterTypes, ["PreviewPipeline", "PlayerFrameSource", "PreviewSink"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "record")?.starterTypes, ["CameraEngine", "RecordingPipeline", "CameraSource"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "timeline")?.starterTypes, ["TimelinePipeline", "TimelineExportTask", "TimelineComposition"])
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "export")?.summary, "Offline export for asset-based workflows.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "preview")?.summary, "Player-frame preview and custom source routing through a lightweight pipeline.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "record")?.summary, "Camera capture and recording with a stable session lifecycle.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "timeline")?.summary, "Layered composition, keyframes, transitions, and audio mix for export planning.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "export")?.usageHint, "Start here when you already have an asset and need offline export.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "preview")?.usageHint, "Start here when you want player frames or a custom source to render into preview.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "record")?.usageHint, "Start here when you need camera capture or recording to file.")
        XCTAssertEqual(KakaposCapabilityCatalog.board(named: "timeline")?.usageHint, "Start here when you need layered composition and export planning.")
        XCTAssertTrue(boards.allSatisfy { $0.primaryTypes.isEmpty == false })
    }

    func testCapabilityCatalogGuideIsCodableForLightweightExternalConsumption() throws {
        let guide = KakaposCapabilityCatalog.guide
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(guide)
        let decoded = try JSONDecoder().decode(KakaposSurfaceGuide.self, from: data)

        XCTAssertEqual(decoded.boardCount, guide.boardCount)
        XCTAssertEqual(decoded.boardNames, guide.boardNames)
        XCTAssertEqual(decoded.starterBoardNames, guide.starterBoardNames)
        XCTAssertEqual(decoded.summaryText, guide.summaryText)
        XCTAssertEqual(decoded.starterText, guide.starterText)
    }

    func testCapabilityCatalogManifestIsCodableForExternalBoardInspection() throws {
        let manifest = KakaposCapabilityCatalog.manifest
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let decoded = try JSONDecoder().decode(KakaposSurfaceManifest.self, from: data)

        XCTAssertEqual(decoded.boardNames, manifest.boardNames)
        XCTAssertEqual(decoded.starterBoardNames, manifest.starterBoardNames)
        XCTAssertEqual(decoded.summaryText, manifest.summaryText)
        XCTAssertEqual(decoded.starterText, manifest.starterText)
        XCTAssertEqual(decoded.boards.map(\.id), manifest.boards.map(\.id))
        XCTAssertEqual(decoded.starterBoards.map(\.id), manifest.starterBoards.map(\.id))
    }

    func testKakaposSurfaceManifestIsCodableAndMatchesTheCapabilityCatalog() throws {
        let manifest = KakaposSurface.manifest
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let decoded = try JSONDecoder().decode(KakaposSurfaceManifest.self, from: data)

        XCTAssertEqual(decoded.boardCount, 4)
        XCTAssertEqual(decoded.starterBoardCount, 4)
        XCTAssertEqual(decoded.boardNames, ["Export", "Preview", "Record", "Timeline"])
        XCTAssertEqual(decoded.starterBoardNames, ["Export", "Preview", "Record", "Timeline"])
        XCTAssertEqual(decoded.summaryText, KakaposCapabilityCatalog.manifest.summaryText)
        XCTAssertEqual(decoded.starterText, KakaposCapabilityCatalog.manifest.starterText)
        XCTAssertEqual(decoded.boards.map(\.id), KakaposCapabilityCatalog.manifest.boards.map(\.id))
        XCTAssertEqual(decoded.starterBoards.map(\.id), KakaposCapabilityCatalog.manifest.starterBoards.map(\.id))
    }

    func testSurfaceSectionIsCodableForCompactBoardManifests() throws {
        let section = try XCTUnwrap(KakaposSurface.section(.preview))
        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(KakaposSurfaceSection.self, from: data)

        XCTAssertEqual(decoded.id, section.id)
        XCTAssertEqual(decoded.displayName, section.displayName)
        XCTAssertEqual(decoded.summary, section.summary)
        XCTAssertEqual(decoded.usageHint, section.usageHint)
        XCTAssertEqual(decoded.primaryTypes, section.primaryTypes)
        XCTAssertEqual(decoded.starterTypes, section.starterTypes)
    }

    func testKakaposSurfaceBoardFacadesMirrorTheCapabilityCatalog() {
        XCTAssertEqual(KakaposSurface.starterBoards.map(\.board), KakaposCapabilityCatalog.starterBoards.map(\.board))
        XCTAssertEqual(KakaposSurface.sections.map(\.board), KakaposCapabilityCatalog.boards.map(\.board))
        XCTAssertEqual(KakaposSurface.guide.summaryText, KakaposCapabilityCatalog.guide.summaryText)
        XCTAssertEqual(KakaposSurface.entries.map(\.id), ["export", "preview", "record", "timeline"])
        XCTAssertEqual(KakaposSurface.entry(.record)?.starterTypesText, "CameraEngine · RecordingPipeline · CameraSource")
        XCTAssertEqual(KakaposSurface.exportBoard.displayName, "Export")
        XCTAssertEqual(KakaposSurface.previewBoard.displayName, "Preview")
        XCTAssertEqual(KakaposSurface.recordBoard.displayName, "Record")
        XCTAssertEqual(KakaposSurface.timelineBoard.displayName, "Timeline")

        XCTAssertEqual(KakaposSurface.exportBoard.starterTypes, ["VideoX", "ReaderWriterExportJob"])
        XCTAssertEqual(KakaposSurface.previewBoard.primaryTypes, ["PreviewPipeline", "PlayerFrameSource", "PreviewSink", "MediaPipeline", "MediaProcessorChain"])
        XCTAssertEqual(KakaposSurface.recordBoard.primaryTypes, ["CameraEngine", "RecordingPipeline", "CameraSource", "CameraDeviceController", "CameraPreviewController", "CameraRecordingController", "RecorderSink", "RecordingSession", "CameraAdvancedOutput"])
        XCTAssertEqual(KakaposSurface.timelineBoard.starterTypes, ["TimelinePipeline", "TimelineExportTask", "TimelineComposition"])
        XCTAssertEqual(KakaposSurface.exportBoard.usageHint, KakaposCapabilityCatalog.board(named: "export")?.usageHint)
        XCTAssertEqual(KakaposSurface.previewBoard.usageHint, KakaposCapabilityCatalog.board(named: "preview")?.usageHint)
        XCTAssertEqual(KakaposSurface.recordBoard.usageHint, KakaposCapabilityCatalog.board(named: "record")?.usageHint)
        XCTAssertEqual(KakaposSurface.timelineBoard.usageHint, KakaposCapabilityCatalog.board(named: "timeline")?.usageHint)

        XCTAssertEqual(KakaposSurface.exportBoard.summary, KakaposCapabilityCatalog.board(named: "export")?.summary)
        XCTAssertEqual(KakaposSurface.previewBoard.summary, KakaposCapabilityCatalog.board(named: "preview")?.summary)
        XCTAssertEqual(KakaposSurface.recordBoard.summary, KakaposCapabilityCatalog.board(named: "record")?.summary)
        XCTAssertEqual(KakaposSurface.timelineBoard.summary, KakaposCapabilityCatalog.board(named: "timeline")?.summary)
        XCTAssertEqual(KakaposSurface.exportBoard.summary, "Offline export for asset-based workflows.")
        XCTAssertEqual(KakaposSurface.previewBoard.summary, "Player-frame preview and custom source routing through a lightweight pipeline.")
        XCTAssertEqual(KakaposSurface.recordBoard.summary, "Camera capture and recording with a stable session lifecycle.")
        XCTAssertEqual(KakaposSurface.timelineBoard.summary, "Layered composition, keyframes, transitions, and audio mix for export planning.")
        XCTAssertEqual(KakaposSurface.section(named: "export")?.starterTypes, ["VideoX", "ReaderWriterExportJob"])
        XCTAssertEqual(KakaposSurface.section(named: "timeline")?.primaryTypes, ["TimelinePipeline", "TimelineExportTask", "TimelineComposition", "ClipLayer", "ImageLayer", "AudioLayer", "EffectLayer", "GroupLayer", "Transition", "KeyframeAnimation"])
    }

    func testKakaposBoardsBuildLightweightEntryPoints() throws {
        let source = TestSource(frames: [])
        let preview = KakaposSurface.preview(source: source) { _, _ in }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let recording = try KakaposSurface.record(source: source, outputURL: outputURL)
        let timeline = KakaposSurface.timeline()

        XCTAssertEqual(preview.summary.sourceTypeName, "TestSource")
        XCTAssertEqual(preview.summary.processorCount, 0)
        XCTAssertEqual(recording.summary.sourceTypeName, "TestSource")
        XCTAssertEqual(recording.summary.processorCount, 0)
        XCTAssertEqual(timeline.summary.layerCount, 0)
        XCTAssertEqual(timeline.summary.transitionCount, 0)
    }

    @available(*, deprecated, message: "Covers the deprecated KakaposBoards alias intentionally.")
    func testKakaposBoardsStarterBoardsMirrorTheSurfaceBoardOrder() {
        XCTAssertEqual(KakaposBoards.starterBoards.map(\.board), KakaposSurface.starterBoards.map(\.board))
        XCTAssertEqual(KakaposBoards.starterBoards.map(\.board), [.export, .preview, .record, .timeline])
    }

    func testKakaposSurfaceExposesTheSameBoardCatalogAsTheLegacyAlias() {
        XCTAssertEqual(KakaposSurface.boards.map(\.board), KakaposCapabilityCatalog.boards.map(\.board))
        XCTAssertEqual(KakaposSurface.guide.boardNamesText, KakaposCapabilityCatalog.guide.boardNamesText)
        XCTAssertEqual(KakaposSurface.board(named: "export")?.starterTypes, ["VideoX", "ReaderWriterExportJob"])
        XCTAssertEqual(KakaposSurface.board(.timeline)?.starterTypes, ["TimelinePipeline", "TimelineExportTask", "TimelineComposition"])
        XCTAssertEqual(KakaposSurface.section(.preview)?.id, "preview")
        XCTAssertEqual(KakaposSurface.section(.export)?.starterTypesText, "VideoX · ReaderWriterExportJob")
        XCTAssertEqual(KakaposSurface.starterEntries.map(\.id), ["export", "preview", "record", "timeline"])
    }

    func testKakaposSurfaceAndBoardsProduceTheSameTimelineExportTaskSummary() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let surfaceTask = KakaposSurface.timelineExportTask(
            layers: [clip],
            outputURL: outputURL
        )
        let boardsTask = KakaposSurface.timelineBoard.timelineExportTask(
            layers: [clip],
            outputURL: outputURL
        )

        XCTAssertEqual(surfaceTask.summary.layerCount, boardsTask.summary.layerCount)
        XCTAssertEqual(surfaceTask.summary.transitionCount, boardsTask.summary.transitionCount)
        XCTAssertEqual(surfaceTask.summary.processorCount, boardsTask.summary.processorCount)
        XCTAssertEqual(surfaceTask.summary.renderSize, boardsTask.summary.renderSize)
    }

    #if canImport(UIKit) || os(macOS)
    func testKakaposSurfaceCanBuildPreviewFromRecordedClip() throws {
        let outputURL = try makeSampleAssetURL()
        let duration = CMTime(value: 30, timescale: 30)
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: .zero,
            endedAt: duration,
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: duration,
                    duration: duration,
                    containsVideo: true,
                    containsAudio: true
                )
            ]
        )

        let surfacePreview = try XCTUnwrap(KakaposSurface.preview(recordedClip: clip, preferredFramesPerSecond: 24) { _, _ in })
        let boardPreview = try XCTUnwrap(KakaposSurface.previewBoard.preview(recordedClip: clip, preferredFramesPerSecond: 24) { _, _ in })

        XCTAssertEqual(surfacePreview.playerSource?.preferredFramesPerSecond, 24)
        XCTAssertEqual(boardPreview.playerSource?.preferredFramesPerSecond, 24)
        XCTAssertEqual(surfacePreview.summary.sourceTypeName, "PlayerFrameSource")
    }
    #endif

    func testKakaposSurfaceCanBuildTimelineAndExportTaskFromRecordedClip() throws {
        let outputURL = try makeSampleAssetURL()
        let duration = CMTime(value: 30, timescale: 30)
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: .zero,
            endedAt: duration,
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: duration,
                    duration: duration,
                    containsVideo: true,
                    containsAudio: true
                )
            ],
            isMutedOnMerge: true
        )
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let surfaceTimeline = try XCTUnwrap(KakaposSurface.timeline(recordedClip: clip))
        let boardTimeline = try XCTUnwrap(KakaposSurface.timelineBoard.timeline(recordedClip: clip))
        let surfaceTask = try XCTUnwrap(KakaposSurface.timelineExportTask(recordedClip: clip, outputURL: exportURL))
        let boardTask = try XCTUnwrap(KakaposSurface.timelineBoard.timelineExportTask(recordedClip: clip, outputURL: exportURL))

        XCTAssertEqual(surfaceTimeline.layers.count, 1)
        XCTAssertEqual(boardTimeline.layers.count, 1)
        XCTAssertEqual(surfaceTask.summary.compiledSummary.videoLayerCount, 1)
        XCTAssertEqual(boardTask.summary.compiledSummary.videoLayerCount, 1)
    }

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

    func testMediaPipelineSummaryDescribesSourceProcessorsSinksAndState() throws {
        let source = TestSource(frames: [])
        let sink = TestSink()
        let processor = ClosureFrameProcessor { frame, completion in
            completion(.success(frame))
        }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])

        XCTAssertEqual(pipeline.snapshot.sourceTypeName, "TestSource")
        XCTAssertEqual(pipeline.snapshot.processorTypeNames, ["ClosureFrameProcessor"])
        XCTAssertEqual(pipeline.snapshot.sinkTypeNames, ["TestSink"])
        XCTAssertEqual(pipeline.snapshot.state, .idle)
        XCTAssertNil(pipeline.snapshot.sourceSnapshot)
        XCTAssertNil(pipeline.snapshot.lastFrameMetadata)
        XCTAssertNil(pipeline.snapshot.lastErrorDescription)
        XCTAssertEqual(pipeline.summary.sourceTypeName, "TestSource")
        XCTAssertEqual(pipeline.summary.processorTypeNames, ["ClosureFrameProcessor"])
        XCTAssertEqual(pipeline.summary.sinkTypeNames, ["TestSink"])
        XCTAssertEqual(pipeline.summary.state, .idle)
        XCTAssertNil(pipeline.summary.sourceSnapshot)
        XCTAssertNil(pipeline.summary.lastFrameIndex)
        XCTAssertNil(pipeline.summary.lastPresentationTime)
        XCTAssertNil(pipeline.summary.lastSourceTime)
        XCTAssertEqual(pipeline.summary.lastErrorDescription, nil)
        XCTAssertEqual(pipeline.summary.summaryText, "source TestSource · processors 1 · sinks 1 · state idle")
        XCTAssertEqual(pipeline.chain.summary.summaryText, "processors 1 · sinks 1")
    }

    func testMediaPipelineSummaryTracksLastFrameMetadataAfterStart() throws {
        let pixelBuffer = try makePixelBuffer(width: 8, height: 8)
        let input = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(
                presentationTime: CMTime(value: 12, timescale: 30),
                sourceTime: CMTime(value: 10, timescale: 30),
                frameIndex: 3
            )
        )
        let source = TestSource(frames: [input])
        let sink = TestSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])

        pipeline.start()

        XCTAssertEqual(pipeline.snapshot.state, .finished)
        XCTAssertEqual(pipeline.snapshot.lastFrameMetadata?.frameIndex, 3)
        XCTAssertEqual(pipeline.snapshot.lastFrameMetadata?.presentationTime, CMTime(value: 12, timescale: 30))
        XCTAssertEqual(pipeline.snapshot.lastFrameMetadata?.sourceTime, CMTime(value: 10, timescale: 30))
        XCTAssertEqual(pipeline.lastFrameMetadata?.frameIndex, 3)
        XCTAssertEqual(pipeline.lastFrameMetadata?.presentationTime, CMTime(value: 12, timescale: 30))
        XCTAssertEqual(pipeline.lastFrameMetadata?.sourceTime, CMTime(value: 10, timescale: 30))
        XCTAssertEqual(
            pipeline.summary.summaryText,
            "source TestSource · processors 0 · sinks 1 · state finished · frame 3 · presentation 0.40s · sourceTime 0.33s"
        )
    }

    func testMediaPipelineSummaryIncludesSourceSnapshotWhenSourceProvidesOne() throws {
        let source = SnapshotSource(
            frames: [],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                details: ["board": "preview"]
            )
        )
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [])

        pipeline.start()

        XCTAssertEqual(pipeline.snapshot.state, .finished)
        XCTAssertEqual(pipeline.snapshot.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(pipeline.snapshot.sourceSnapshot?.details["board"], "preview")
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.stateDescription, "primed")
        XCTAssertTrue(pipeline.summary.summaryText.contains("sourceSnapshot state primed"))
    }

    func testMediaPipelineManifestIsCodableForExternalInspection() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let input = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(
                presentationTime: CMTime(value: 18, timescale: 30),
                sourceTime: CMTime(value: 15, timescale: 30),
                frameIndex: 9
            )
        )
        let source = SnapshotSource(
            frames: [input],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                lastFrameIndex: 9,
                lastPresentationTime: .zero,
                lastSourceTime: .zero,
                details: ["board": "media"]
            )
        )
        let sink = TestSink()
        let processor = ClosureFrameProcessor { frame, completion in
            completion(.success(frame))
        }
        let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])

        pipeline.start()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pipeline.manifest)
        let decoded = try JSONDecoder().decode(MediaPipeline.Manifest.self, from: data)

        XCTAssertEqual(decoded.sourceTypeName, "SnapshotSource")
        XCTAssertEqual(decoded.processorTypeNames, ["ClosureFrameProcessor"])
        XCTAssertEqual(decoded.sinkTypeNames, ["TestSink"])
        XCTAssertEqual(decoded.stateDescription, "finished")
        XCTAssertEqual(decoded.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(decoded.sourceSnapshot?.lastFrameIndex, 9)
        XCTAssertEqual(decoded.sourceSnapshot?.details["board"], "media")
        let lastFrameMetadata = try XCTUnwrap(decoded.lastFrameMetadata)
        XCTAssertEqual(lastFrameMetadata.frameIndex, 9)
        XCTAssertEqual(lastFrameMetadata.presentationTimeSeconds, 0.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(lastFrameMetadata.sourceTimeSeconds), 0.5, accuracy: 0.0001)
        XCTAssertEqual(lastFrameMetadata.trackTransformA, 1, accuracy: 0.0001)
        XCTAssertEqual(lastFrameMetadata.trackTransformD, 1, accuracy: 0.0001)
        XCTAssertEqual(decoded.lastErrorDescription, nil)
    }

    #if canImport(UIKit) || os(macOS)
    func testMediaPipelinePlayerInitializerUsesPlayerFrameSource() {
        let player = AVPlayer()
        let sink = TestSink()
        let pipeline = MediaPipeline(player: player, processors: [], sinks: [sink])

        XCTAssertTrue(pipeline.source is PlayerFrameSource)
        XCTAssertEqual(pipeline.sinks.count, 1)
        XCTAssertEqual(pipeline.snapshot.sourceTypeName, "PlayerFrameSource")
        XCTAssertNotNil(pipeline.summary.sourceSnapshot)
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.details["generation"], "0")
        XCTAssertEqual(pipeline.snapshot.sourceSnapshot?.details["generation"], "0")
        XCTAssertTrue(pipeline.summary.summaryText.contains("sourceSnapshot state idle"))
        XCTAssertTrue(pipeline.summary.summaryText.contains("generation 0"))
    }
    #endif

    func testImageSourceCanBroadcastFramesDirectlyToConsumerNode() throws {
        let frame = StillImageFrame(image: try makeImage(width: 16, height: 16))
        let callbackQueue = DispatchQueue(label: "com.condy.kakapos.tests.image-source.direct")
        let source = ImageSource(frames: [frame], callbackQueue: callbackQueue)
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
        let callbackQueue = DispatchQueue(label: "com.condy.kakapos.tests.image-source.pipeline")
        let source = ImageSource(frames: frames, renderSize: CGSize(width: 40, height: 24), callbackQueue: callbackQueue)
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
        XCTAssertEqual(compiled.summary.renderSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(compiled.summary.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(
            compiled.summary.summaryText,
            "size 1920x1080 · frame 30fps · video 0 · image 0 · text 0 · effect 0 · transitions 0 · intervals 0 · segments 0/0/0 · audio 0/0 · transitionSegments 0 · tracks 0/0 · sources 0 · processors 0"
        )
    }

    func testTimelineCompositionProducesCompilationSummaryForMixedLayers() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let image = ImageLayer(
            image: try makeImage(width: 32, height: 18),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 1
        )
        let effect = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            source: EffectSource(processor: PassthroughFrameProcessor(), intensity: 0.6),
            layerLevel: 2
        )
        let firstClip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 0
        )
        let secondClip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 3
        )
        let transitionRange = CMTimeRange(start: .zero, duration: CMTime(value: 15, timescale: 30))
        let timeline = TimelineComposition(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [firstClip, secondClip, image, effect],
            transitions: [
                Transition(timeRange: transitionRange, sourceLayerLevel: 0, destinationLayerLevel: 3)
            ]
        )

        let compiled = timeline.compile()

        XCTAssertEqual(compiled.summary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(compiled.summary.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(compiled.summary.videoLayerCount, 2)
        XCTAssertEqual(compiled.summary.imageLayerCount, 1)
        XCTAssertEqual(compiled.summary.textLayerCount, 0)
        XCTAssertEqual(compiled.summary.effectLayerCount, 1)
        XCTAssertEqual(compiled.summary.transitionCount, 1)
        XCTAssertEqual(compiled.summary.visualIntervalCount, 1)
        XCTAssertEqual(compiled.summary.assetSegmentCount, 2)
        XCTAssertEqual(compiled.summary.imageSegmentCount, 1)
        XCTAssertEqual(compiled.summary.textSegmentCount, 0)
        XCTAssertEqual(compiled.summary.audioSegmentCount, 2)
        XCTAssertEqual(compiled.summary.audioMixSegmentCount, 2)
        XCTAssertEqual(compiled.summary.transitionSegmentCount, 1)
        XCTAssertEqual(compiled.summary.videoTrackCount, 2)
        XCTAssertEqual(compiled.summary.audioTrackCount, 2)
        XCTAssertEqual(compiled.summary.sourceTrackIDCount, 4)
        XCTAssertEqual(compiled.summary.processorCount, 1)
        XCTAssertEqual(
            compiled.summary.summaryText,
            "size 1280x720 · frame 30fps · video 2 · image 1 · text 0 · effect 1 · transitions 1 · intervals 1 · segments 2/1/0 · audio 2/2 · transitionSegments 1 · tracks 2/2 · sources 4 · processors 1"
        )
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

    func testTimelineCompositionExposesTransitionAndAudioMixPlans() throws {
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
            transitions: [
                Transition(
                    timeRange: transitionRange,
                    sourceLayerLevel: 0,
                    destinationLayerLevel: 1,
                    audioBehavior: .crossfade,
                    timingFunction: .easeInOut
                )
            ]
        )

        let compiled = timeline.compile()
        let transitionSegment = try XCTUnwrap(compiled.renderPlan.transitionSegments.first)
        let transitionInterval = try XCTUnwrap(compiled.renderPlan.visualIntervals.first(where: { $0.timeRange == transitionRange }))
        let fadeOut = try XCTUnwrap(compiled.renderPlan.audioMixSegments.first(where: { $0.kind == .transitionFadeOut }))
        let fadeIn = try XCTUnwrap(compiled.renderPlan.audioMixSegments.first(where: { $0.kind == .transitionFadeIn }))

        XCTAssertEqual(compiled.renderPlan.transitionSegments.count, 1)
        XCTAssertEqual(transitionSegment.timeRange, transitionRange)
        XCTAssertEqual(transitionSegment.sourceLayerLevel, 0)
        XCTAssertEqual(transitionSegment.destinationLayerLevel, 1)
        XCTAssertEqual(transitionSegment.transition.timingFunction, .easeInOut)
        XCTAssertEqual(transitionInterval.transitionSegments.count, 1)
        XCTAssertEqual(fadeOut.timeRange, transitionRange)
        XCTAssertEqual(fadeIn.timeRange, transitionRange)
        XCTAssertEqual(fadeOut.startVolume, 0.8, accuracy: 0.0001)
        XCTAssertEqual(fadeOut.endVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(fadeIn.startVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(fadeIn.endVolume, 0.6, accuracy: 0.0001)
        XCTAssertEqual(fadeOut.timingFunction, .easeInOut)
        XCTAssertEqual(fadeIn.timingFunction, .easeInOut)
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
        let layerRamp = try XCTUnwrap(compiled.renderPlan.audioMixSegments.first(where: { $0.kind == .layerRamp }))
        XCTAssertEqual(layerRamp.timeRange, rampRange)
        XCTAssertEqual(layerRamp.startVolume, 0.1, accuracy: 0.0001)
        XCTAssertEqual(layerRamp.endVolume, 0.5, accuracy: 0.0001)
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

        let callbackQueue = DispatchQueue(label: "com.condy.kakapos.tests.timeline.image-source")
        let imageSource = try XCTUnwrap(compiled.makeImageSource(callbackQueue: callbackQueue))
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
        XCTAssertEqual(info.phase, .idle)
    }

    func testReaderWriterProgressInfoTracksExportPhaseUpdates() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        job._setStatusForTesting(.exporting)

        job._setProgressInfoForTesting(
            ReaderWriterExportJob.ProgressInfo(
                videoProgress: 0.3,
                audioProgress: 0.0,
                hasVideo: true,
                hasAudio: false,
                phase: .videoEncoding
            )
        )
        XCTAssertEqual(job.lastProgressInfo?.phase, .videoEncoding)

        job._setProgressInfoForTesting(
            ReaderWriterExportJob.ProgressInfo(
                videoProgress: 0.7,
                audioProgress: 0.6,
                hasVideo: true,
                hasAudio: true,
                finishWritingProgress: 0.1,
                phase: .finishing
            )
        )
        XCTAssertEqual(job.lastProgressInfo?.phase, .finishing)
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
        XCTAssertEqual(info.overallFractionCompleted, 1.0, accuracy: 0.0001)
    }

    func testReaderWriterProgressInfoUsesTheHigherOfEncodingAndFinishProgress() {
        let info = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.2,
            audioProgress: 0.4,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.1,
            phase: .finishing
        )

        XCTAssertEqual(info.fractionCompleted, 0.3, accuracy: 0.0001)
        XCTAssertEqual(info.overallFractionCompleted, 0.3, accuracy: 0.0001)
    }

    func testReaderWriterExportJobStoresLatestProgressSnapshot() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let progress = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.25,
            audioProgress: 0.75,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.5
        )

        job._setStatusForTesting(.exporting)
        job._setProgressInfoForTesting(progress)

        XCTAssertNotNil(job.lastProgressInfo)
        guard let lastProgressInfo = job.lastProgressInfo else { return }
        XCTAssertEqual(lastProgressInfo.videoProgress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(lastProgressInfo.audioProgress, 0.75, accuracy: 0.0001)
        XCTAssertEqual(lastProgressInfo.finishWritingProgress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(lastProgressInfo.overallFractionCompleted, progress.overallFractionCompleted, accuracy: 0.0001)
        XCTAssertEqual(lastProgressInfo.phase, .idle)
        XCTAssertEqual(Double(job.progressFraction ?? 0), progress.overallFractionCompleted, accuracy: 0.0001)
    }

    func testReaderWriterExportJobSnapshotTracksConfigurationAndRuntimeState() {
        let asset = AVMutableComposition()
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = .commonIdentifierTitle
        metadataItem.value = "Kakapos" as NSString

        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov"),
            fileType: .mov,
            timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 60, timescale: 30)),
            videoComposition: AVMutableVideoComposition(),
            audioMix: AVMutableAudioMix(),
            videoProcessors: [PassthroughFrameProcessor()],
            shouldOptimizeForNetworkUse: false,
            metadata: [metadataItem]
        )
        let progress = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.25,
            audioProgress: 0.75,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.5,
            phase: .finishing
        )

        job._setStatusForTesting(.exporting)
        job._setProgressInfoForTesting(progress)

        let snapshot = job.snapshot

        XCTAssertEqual(snapshot.status, .exporting)
        XCTAssertEqual(snapshot.fileType, .mov)
        XCTAssertEqual(snapshot.timeRange, CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 60, timescale: 30)))
        XCTAssertFalse(snapshot.shouldOptimizeForNetworkUse)
        XCTAssertEqual(snapshot.metadataCount, 1)
        XCTAssertEqual(snapshot.videoTrackCount, 0)
        XCTAssertEqual(snapshot.audioTrackCount, 0)
        XCTAssertEqual(snapshot.processorCount, 1)
        XCTAssertTrue(snapshot.hasVideoComposition)
        XCTAssertTrue(snapshot.hasAudioMix)
        XCTAssertEqual(snapshot.lastPhase, .finishing)
        XCTAssertEqual(snapshot.progressFraction ?? 0, progress.overallFractionCompleted, accuracy: 0.0001)
        XCTAssertEqual(snapshot.lastErrorDescription, nil)
        XCTAssertEqual(job.summary.status, snapshot.status)
        XCTAssertEqual(job.summary.lastPhase, snapshot.lastPhase)
        XCTAssertEqual(job.summary.lastProgressInfo, snapshot.lastProgressInfo)
    }

    func testReaderWriterExportJobSummaryReflectsTracksProcessorsAndProgress() {
        let asset = AVMutableComposition()
        let videoTrack = asset.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = asset.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        XCTAssertNotNil(videoTrack)
        XCTAssertNotNil(audioTrack)

        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4"),
            videoProcessors: [PassthroughFrameProcessor()]
        )
        job._setStatusForTesting(.exporting)
        job._setProgressInfoForTesting(
            ReaderWriterExportJob.ProgressInfo(
                videoProgress: 0.4,
                audioProgress: 0.8,
                hasVideo: true,
                hasAudio: true,
                finishWritingProgress: 0.2,
                phase: .finishing
            )
        )

        XCTAssertEqual(job.summary.videoTrackCount, 1)
        XCTAssertEqual(job.summary.audioTrackCount, 1)
        XCTAssertEqual(job.summary.processorCount, 1)
        XCTAssertEqual(job.summary.status, .exporting)
        XCTAssertEqual(
            job.summary.summaryText,
            "state exporting · tracks 1/1 · processors 1 · progress 60% · phase finishing · video 40% · audio 80% · finish 20%"
        )
    }

    func testReaderWriterExportJobConfigurationSummaryDescribesExportInputs() {
        let asset = AVMutableComposition()
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = .commonIdentifierTitle
        metadataItem.value = "Kakapos" as NSString

        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov"),
            fileType: .mov,
            timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 60, timescale: 30)),
            videoComposition: AVMutableVideoComposition(),
            audioMix: AVMutableAudioMix(),
            videoProcessors: [PassthroughFrameProcessor()],
            shouldOptimizeForNetworkUse: false,
            metadata: [metadataItem]
        )

        XCTAssertEqual(
            job.configurationSummaryText,
            "file com.apple.quicktime-movie · range 0.50s→2.50s · processors 1 · metadata 1 · network no · videoComposition yes · audioMix yes"
        )
        XCTAssertTrue(job.summary.summaryText.contains("tracks 0/0"))
    }

    func testReaderWriterExportJobManifestIsCodableForExternalInspection() throws {
        let asset = AVMutableComposition()
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = .commonIdentifierTitle
        metadataItem.value = "Kakapos" as NSString

        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov"),
            fileType: .mov,
            timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 60, timescale: 30)),
            videoComposition: AVMutableVideoComposition(),
            audioMix: AVMutableAudioMix(),
            videoProcessors: [PassthroughFrameProcessor()],
            shouldOptimizeForNetworkUse: false,
            metadata: [metadataItem]
        )
        job._setStatusForTesting(.exporting)
        let progress = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.4,
            audioProgress: 0.8,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.2,
            phase: .finishing
        )
        job._setProgressInfoForTesting(progress)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(job.manifest)
        let decoded = try JSONDecoder().decode(ReaderWriterExportJob.Manifest.self, from: data)

        XCTAssertEqual(decoded.status, .exporting)
        XCTAssertEqual(decoded.fileTypeRawValue, AVFileType.mov.rawValue)
        XCTAssertEqual(decoded.timeRange.startSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(decoded.timeRange.durationSeconds), 2.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(decoded.timeRange.endSeconds), 2.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.timeRange.isInfinite, false)
        XCTAssertEqual(decoded.shouldOptimizeForNetworkUse, false)
        XCTAssertEqual(decoded.metadataCount, 1)
        XCTAssertEqual(decoded.videoTrackCount, 0)
        XCTAssertEqual(decoded.audioTrackCount, 0)
        XCTAssertEqual(decoded.processorCount, 1)
        XCTAssertTrue(decoded.hasVideoComposition)
        XCTAssertTrue(decoded.hasAudioMix)
        XCTAssertEqual(decoded.lastPhase, .finishing)
        XCTAssertEqual(try XCTUnwrap(decoded.lastProgressInfo).overallFractionCompleted, progress.overallFractionCompleted, accuracy: 0.0001)
        XCTAssertEqual(decoded.lastErrorDescription, nil)
    }

    func testExportSessionProgressObserverTracksKvoProgressChanges() {
        let session = ObservableProgressSession()
        var receivedValues: [Float] = []
        let updateExpectation = expectation(description: "progress updates")
        updateExpectation.expectedFulfillmentCount = 3

        let observer = ExportSessionProgressObserver(session: session, keyPath: \.progress) { value in
            receivedValues.append(value)
            updateExpectation.fulfill()
        }

        observer.start()
        session.progress = 0.35
        session.progress = 0.8

        wait(for: [updateExpectation], timeout: 1)
        observer.stop()

        XCTAssertEqual(receivedValues.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(receivedValues.last ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(receivedValues.count, 3)
    }

    func testReaderWriterExportJobSummaryIncludesFailureDescription() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let completionExpectation = expectation(description: "reader writer export failure")

        job.export { result in
            if case .success(let outputURL) = result {
                XCTFail("Unexpected reader/writer export success: \(outputURL)")
            }
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(job.status, .failed)
        XCTAssertNotNil(job.lastErrorDescription)
        XCTAssertTrue(job.summary.summaryText.contains("error"))
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

    func testReaderWriterExportJobClearsStaleOutputBeforeStartingNewExport() throws {
        let session = FakeReaderWriterExportSession()
        let asset = AVAsset(url: try makeSampleAssetURL())
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: outputURL,
            sessionFactory: { _, _, _ in session }
        )
        let completionExpectation = expectation(description: "export completion")
        let statusExpectation = expectation(description: "completed status callback")
        var receivedStatuses: [ReaderWriterExportJob.Status] = []

        FileManager.default.createFile(atPath: outputURL.path, contents: Data("stale".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        job.statusHandler = { status in
            receivedStatuses.append(status)
            if status == .completed {
                statusExpectation.fulfill()
            }
        }

        job.export { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected export failure: \(error)")
            }
            completionExpectation.fulfill()
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        session.finish(with: nil)

        wait(for: [completionExpectation, statusExpectation], timeout: 1)
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(receivedStatuses, [.exporting, .completed])
    }

    func testReaderWriterExportJobIgnoresLateProgressAndStatusAfterCompletion() {
        let job = ReaderWriterExportJob(
            asset: AVMutableComposition(),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
        )
        let initialProgress = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.25,
            audioProgress: 0.5,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.1
        )
        let lateProgress = ReaderWriterExportJob.ProgressInfo(
            videoProgress: 0.9,
            audioProgress: 0.9,
            hasVideo: true,
            hasAudio: true,
            finishWritingProgress: 0.9
        )

        job._setStatusForTesting(.exporting)
        job._setProgressInfoForTesting(initialProgress)
        XCTAssertEqual(job.lastProgressInfo?.overallFractionCompleted, initialProgress.overallFractionCompleted)

        job._setStatusForTesting(.completed)
        job._setProgressInfoForTesting(lateProgress)
        job._setStatusForTesting(.failed)

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.lastProgressInfo?.overallFractionCompleted, initialProgress.overallFractionCompleted)
        XCTAssertTrue(job.summary.summaryText.contains("state completed"))
        XCTAssertFalse(job.summary.summaryText.contains("error"))
    }

    func testReaderWriterExportJobIgnoresLateSessionCallbacksAfterCompletion() throws {
        let session = FakeReaderWriterExportSession()
        let asset = AVAsset(url: try makeSampleAssetURL())
        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4"),
            sessionFactory: { _, _, _ in session }
        )
        let completionExpectation = expectation(description: "export completion")
        let statusExpectation = expectation(description: "status callbacks")
        statusExpectation.expectedFulfillmentCount = 2
        var receivedStatuses: [ReaderWriterExportJob.Status] = []
        var receivedResult: Result<URL, Error>?

        job.statusHandler = { status in
            receivedStatuses.append(status)
            statusExpectation.fulfill()
        }

        job.export { result in
            receivedResult = result
            completionExpectation.fulfill()
        }

        session.emitStatus(.exporting)
        session.emitProgress(
            ReaderWriterExportSessionProgress(
                videoProgress: 0.2,
                audioProgress: 0.4,
                hasVideo: true,
                hasAudio: true,
                finishWritingProgress: 0.1
            )
        )
        XCTAssertEqual(job.lastProgressInfo?.phase, .finishing)
        session.finish(with: nil)

        wait(for: [completionExpectation, statusExpectation], timeout: 1)
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(receivedStatuses, [.exporting, .completed])
        XCTAssertNotNil(job.lastProgressInfo)
        XCTAssertEqual(job.lastProgressInfo?.overallFractionCompleted ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(job.lastProgressInfo?.phase, .finishing)
        if case .failure(let error)? = receivedResult {
            XCTFail("Unexpected export failure: \(error)")
        }

        session.emitStatus(.failed)
        session.emitProgress(
            ReaderWriterExportSessionProgress(
                videoProgress: 0.9,
                audioProgress: 0.9,
                hasVideo: true,
                hasAudio: true,
                finishWritingProgress: 0.9
            )
        )

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(receivedStatuses, [.exporting, .completed])
        XCTAssertNotNil(job.lastProgressInfo)
        XCTAssertEqual(job.lastProgressInfo?.overallFractionCompleted ?? -1, 0.3, accuracy: 0.0001)
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

    func testReaderWriterExportJobCancelWhileExportingUpdatesStatusImmediately() throws {
        let session = FakeReaderWriterExportSession()
        let asset = AVAsset(url: try makeSampleAssetURL())
        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4"),
            sessionFactory: { _, _, _ in session }
        )
        let statusExpectation = expectation(description: "cancel status")
        var receivedStatuses: [ReaderWriterExportJob.Status] = []
        job.statusHandler = { status in
            receivedStatuses.append(status)
            if status == .cancelled {
                statusExpectation.fulfill()
            }
        }

        job.export { _ in }
        session.emitStatus(.exporting)

        XCTAssertEqual(job.status, .exporting)

        job.cancel()

        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(session.cancelCallCount, 1)

        wait(for: [statusExpectation], timeout: 1)
        XCTAssertEqual(receivedStatuses, [.exporting, .cancelled])
    }

    func testReaderWriterExportJobCancelWhileExportingRemovesPartialOutputImmediately() throws {
        let session = FakeReaderWriterExportSession()
        let asset = AVAsset(url: try makeSampleAssetURL())
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let job = ReaderWriterExportJob(
            asset: asset,
            outputURL: outputURL,
            sessionFactory: { _, _, _ in session }
        )
        let cancelExpectation = expectation(description: "cancel status")
        let completionExpectation = expectation(description: "cancel completion")
        var receivedStatuses: [ReaderWriterExportJob.Status] = []

        job.statusHandler = { status in
            receivedStatuses.append(status)
            if status == .cancelled {
                cancelExpectation.fulfill()
            }
        }

        job.export { result in
            if case .failure(let error) = result {
                guard case VideoX.Error.exportCancelled = VideoX.Error.toError(error) else {
                    return XCTFail("Expected cancelled export failure")
                }
            } else {
                XCTFail("Expected cancelled export failure")
            }
            completionExpectation.fulfill()
        }
        session.emitStatus(.exporting)
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("partial".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        job.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(session.cancelCallCount, 1)
        wait(for: [cancelExpectation, completionExpectation], timeout: 1)

        session.finish(with: nil)
        session.emitStatus(.failed)

        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(receivedStatuses, [.exporting, .cancelled])
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
        XCTAssertEqual(outputURL.pathExtension.lowercased(), "mov")
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

    func testVideoXReaderWriterExportExtractsNestedProcessorInstructions() throws {
        let exporter = try makeSampleExporter()
        let nestedInstruction = CompositeInstruction(instructions: [
            CompositeInstruction(instructions: [
                FilterInstruction(processor: PassthroughFrameProcessor()),
                RotateInstruction(rotationAngle: .angle90)
            ])
        ])

        let exportJob = try XCTUnwrap(
            exporter.makeExportJob(
                options: [.ExportPipeline: VideoX.ExportPipeline.readerWriter],
                instructions: [nestedInstruction]
            )
        )

        XCTAssertEqual(exportJob._videoProcessorCountForTesting, 1)
    }

    func testVideoXAssetExportSessionUsesNestedRotateInstructionsForRenderSize() throws {
        let exporter = try makeSampleExporter()
        let nestedInstruction = CompositeInstruction(instructions: [
            CompositeInstruction(instructions: [
                RotateInstruction(rotationAngle: .angle90)
            ])
        ])

        let exportSession = try exporter.makeAssetExportSession(instructions: [nestedInstruction])
        let expectedSize = VideoX.Option.setupVideoRenderSize(
            exporter.provider.videoTracks,
            asset: exporter.provider.asset,
            options: [:]
        )
        let swappedSize = CGSize(width: expectedSize.height, height: expectedSize.width)

        XCTAssertEqual(exportSession.videoComposition?.renderSize, swappedSize)
    }

    func testReaderWriterExportJobInvokesFrameProcessorDuringExport() throws {
        let callbackExpectation = expectation(description: "frame processor invoked")
        let exportExpectation = expectation(description: "reader writer export finished")
        callbackExpectation.assertForOverFulfill = false
        var invocationCount = 0

        let processor = ClosureFrameProcessor { frame, completion in
            invocationCount += 1
            callbackExpectation.fulfill()
            completion(.success(frame))
        }

        let exportJob = ReaderWriterExportJob(
            asset: AVAsset(url: try makeSampleAssetURL()),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov"),
            fileType: .mov,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 5)),
            videoComposition: nil,
            audioMix: nil,
            videoProcessors: [processor],
            shouldOptimizeForNetworkUse: true,
            metadata: [],
            sessionFactory: { _, outputURL, configuration in
                let syntheticBuffer = try makePixelBuffer(width: 16, height: 16)
                let frame = MediaFrame(
                    pixelBuffer: syntheticBuffer,
                    metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
                )
                return SyntheticReaderWriterExportSession(
                    processors: configuration.videoProcessors,
                    frame: frame,
                    outputURL: outputURL
                )
            }
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

        XCTAssertEqual(exportTask.summaryText, "state idle · assetExportSession")
    }

    func testVideoXExportTaskInitializesLegacyAssetSessionState() throws {
        let exporter = try makeSampleExporter()
        let exportTask = try exporter.makeExportTask(
            options: [:],
            instructions: []
        )

        XCTAssertNotNil(exportTask.assetExportSession)
        XCTAssertNil(exportTask.readerWriterJob)
        XCTAssertEqual(exportTask.progressFraction, nil)
        XCTAssertEqual(exportTask.status, .idle)
        XCTAssertEqual(exportTask.summaryText, "state idle · assetExportSession")
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
        XCTAssertEqual(exportTask.summaryText, "state idle · tracks 1/1 · processors 1 · progress n/a · phase idle")
        XCTAssertEqual(
            exportTask.configurationSummaryText,
            "file com.apple.quicktime-movie · range 0.00s→10.07s · processors 1 · metadata 0 · network yes · videoComposition no · audioMix yes"
        )

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
        job._setStatusForTesting(.completed)
        XCTAssertEqual(task.status, .completed)
        job._setStatusForTesting(.failed)
        XCTAssertEqual(task.status, .completed)
    }

    func testVideoXExportTaskForwardsReaderWriterProgressSnapshots() throws {
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let syntheticFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 16, height: 16),
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let exportJob = ReaderWriterExportJob(
            asset: AVAsset(url: try makeSampleAssetURL()),
            outputURL: exportURL,
            fileType: .mov,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 5)),
            videoComposition: nil,
            audioMix: nil,
            videoProcessors: [PassthroughFrameProcessor()],
            shouldOptimizeForNetworkUse: true,
            metadata: [],
            sessionFactory: { _, outputURL, configuration in
                SyntheticReaderWriterExportSession(
                    processors: configuration.videoProcessors,
                    frame: syntheticFrame,
                    outputURL: outputURL
                )
            }
        )
        let exportTask = VideoX.ExportTask(readerWriterJob: exportJob)

        let progressExpectation = expectation(description: "progress snapshot")
        let completionExpectation = expectation(description: "reader writer export finished")
        progressExpectation.assertForOverFulfill = false
        var receivedProgressInfo: ReaderWriterExportJob.ProgressInfo?

        exportTask.start(
            complete: { result in
                if case .failure(let error) = result {
                    XCTFail("Unexpected reader/writer export failure: \(error)")
                }
                completionExpectation.fulfill()
            },
            progress: nil,
            progressInfo: { info in
                receivedProgressInfo = info
                progressExpectation.fulfill()
            }
        )

        wait(for: [progressExpectation, completionExpectation], timeout: 15)
        XCTAssertNotNil(receivedProgressInfo)
        XCTAssertGreaterThanOrEqual(receivedProgressInfo?.overallFractionCompleted ?? 0, 0)
        XCTAssertLessThanOrEqual(receivedProgressInfo?.overallFractionCompleted ?? 0, 1)
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

    func testPreviewSinkSummaryReflectsPauseResumeAndBufferedFrameState() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(pixelBuffer: firstBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let second = MediaFrame(pixelBuffer: secondBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30), frameIndex: 2))
        let sink = PreviewSink { _, _ in }

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(sink.summary.state, .active)
        XCTAssertEqual(sink.summary.lastFrameIndex, 1)
        XCTAssertEqual(sink.summary.lastImageWidth, 10)
        XCTAssertEqual(sink.summary.lastPresentationTime, .zero)
        XCTAssertEqual(sink.summary.lastSourceTime, .zero)
        XCTAssertNil(sink.summary.lastFrameRequestReason)
        XCTAssertEqual(
            sink.summary.summaryText,
            "state active · frame 1 · presentation 0.00s · sourceTime 0.00s · reason n/a · image 10x8 · pending no"
        )

        sink.pause()
        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(sink.summary.state, .paused)
        XCTAssertEqual(sink.summary.hasPendingFrame, true)
        XCTAssertEqual(sink.summary.lastFrameIndex, 1)
        XCTAssertEqual(
            sink.summary.summaryText,
            "state paused · frame 1 · presentation 0.00s · sourceTime 0.00s · reason n/a · image 10x8 · pending yes"
        )
    }

    func testPreviewSinkSnapshotMirrorsSummaryStateAndPendingFrame() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(pixelBuffer: firstBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let pending = MediaFrame(
            pixelBuffer: secondBuffer,
            metadata: FrameMetadata(
                presentationTime: CMTime(value: 1, timescale: 30),
                sourceTime: CMTime(value: 1, timescale: 30),
                frameIndex: 2,
                userInfo: [PlayerFrameSource.MetadataKey.frameRequestReason: "seek"]
            )
        )
        let sink = PreviewSink { _, _ in }

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }
        sink.pause()
        sink.consume(pending) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        let snapshot = sink.snapshot
        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.lastFrameIndex, 1)
        XCTAssertEqual(snapshot.lastImageWidth, 10)
        XCTAssertEqual(snapshot.lastImageHeight, 8)
        XCTAssertTrue(snapshot.hasPendingFrame)
        XCTAssertEqual(snapshot.pendingFrameIndex, 2)
        XCTAssertEqual(snapshot.pendingFrameRequestReason, "seek")
        XCTAssertEqual(snapshot.pendingFrameSourceTime, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(sink.summary.state, snapshot.state)
        XCTAssertEqual(sink.summary.lastFrameIndex, snapshot.lastFrameIndex)
        XCTAssertEqual(sink.summary.pendingFrameIndex, snapshot.pendingFrameIndex)
        XCTAssertEqual(sink.summary.summaryText, "state paused · frame 1 · presentation 0.00s · sourceTime 0.00s · reason n/a · image 10x8 · pending yes · pendingFrame 2 · pendingPresentation 0.03s · pendingSourceTime 0.03s · pendingReason seek")
    }

    func testPreviewSinkSummaryCapturesFrameRequestReasonFromMetadata() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let metadata = FrameMetadata(
            presentationTime: CMTime(value: 5, timescale: 30),
            sourceTime: CMTime(value: 4, timescale: 30),
            frameIndex: 3,
            userInfo: ["kakapos.player-frame-request-reason": "seek"]
        )
        let sink = PreviewSink { _, _ in }

        sink.consume(MediaFrame(pixelBuffer: pixelBuffer, metadata: metadata)) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(sink.summary.lastFrameRequestReason, "seek")
        XCTAssertEqual(
            sink.summary.summaryText,
            "state active · frame 3 · presentation 0.17s · sourceTime 0.13s · reason seek · image 12x10 · pending no"
        )
    }

    func testPreviewSinkSummaryIncludesPendingFrameReasonWhilePaused() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(
            pixelBuffer: firstBuffer,
            metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1)
        )
        let pendingMetadata = FrameMetadata(
            presentationTime: CMTime(value: 1, timescale: 30),
            sourceTime: CMTime(value: 1, timescale: 30),
            frameIndex: 2,
            userInfo: [PlayerFrameSource.MetadataKey.frameRequestReason: "seek"]
        )
        let sink = PreviewSink { _, _ in }

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }

        sink.pause()
        sink.consume(MediaFrame(pixelBuffer: secondBuffer, metadata: pendingMetadata)) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(sink.summary.state, .paused)
        XCTAssertEqual(sink.summary.hasPendingFrame, true)
        XCTAssertEqual(sink.summary.pendingFrameIndex, 2)
        XCTAssertEqual(sink.summary.pendingFrameRequestReason, "seek")
        XCTAssertEqual(
            sink.summary.summaryText,
            "state paused · frame 1 · presentation 0.00s · sourceTime 0.00s · reason n/a · image 10x8 · pending yes · pendingFrame 2 · pendingPresentation 0.03s · pendingSourceTime 0.03s · pendingReason seek"
        )
    }

    func testPreviewPipelineSummarySurfacesPendingFrameReasonWhilePaused() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(
            pixelBuffer: firstBuffer,
            metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1)
        )
        let pendingMetadata = FrameMetadata(
            presentationTime: CMTime(value: 1, timescale: 30),
            sourceTime: CMTime(value: 1, timescale: 30),
            frameIndex: 2,
            userInfo: [PlayerFrameSource.MetadataKey.frameRequestReason: "seek"]
        )
        let source = ManualSource()
        let pipeline = PreviewPipeline(source: source) { _, _ in }

        pipeline.start()
        source.emit(first)
        pipeline.pause()
        pipeline.previewSink.consume(MediaFrame(pixelBuffer: secondBuffer, metadata: pendingMetadata)) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused preview sink failure: \(error)")
            }
        }

        XCTAssertEqual(pipeline.previewSink.summary.state, .paused)
        XCTAssertEqual(pipeline.summary.previewState, .paused)
        XCTAssertEqual(pipeline.summary.pendingFrameIndex, 2)
        XCTAssertEqual(pipeline.summary.pendingFrameRequestReason, "seek")
        XCTAssertEqual(
            pipeline.summary.summaryText,
            "source ManualSource · processors 0 · pipeline paused · preview paused · frame 1 · presentation 0.00s · pendingFrame 2 · pendingPresentation 0.03s · pendingSourceTime 0.03s · pendingReason seek"
        )
    }

    func testPreviewPipelinePreviewSnapshotExposesUnderlyingPreviewSinkSnapshot() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(
            pixelBuffer: firstBuffer,
            metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1)
        )
        let pendingMetadata = FrameMetadata(
            presentationTime: CMTime(value: 1, timescale: 30),
            sourceTime: CMTime(value: 1, timescale: 30),
            frameIndex: 2,
            userInfo: [PlayerFrameSource.MetadataKey.frameRequestReason: "seek"]
        )
        let source = ManualSource()
        let pipeline = PreviewPipeline(source: source) { _, _ in }

        pipeline.start()
        source.emit(first)
        pipeline.pause()
        pipeline.previewSink.consume(MediaFrame(pixelBuffer: secondBuffer, metadata: pendingMetadata)) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected paused preview sink failure: \(error)")
            }
        }

        let snapshot = pipeline.previewSnapshot
        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.lastFrameIndex, 1)
        XCTAssertEqual(snapshot.pendingFrameIndex, 2)
        XCTAssertEqual(snapshot.pendingFrameRequestReason, "seek")
        XCTAssertEqual(pipeline.summary.previewState, snapshot.state)
        XCTAssertEqual(pipeline.summary.pendingFrameIndex, snapshot.pendingFrameIndex)
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

    func testPreviewSinkIgnoresLateFramesAfterCancelAndFinish() throws {
        let firstBuffer = try makePixelBuffer(width: 10, height: 8)
        let secondBuffer = try makePixelBuffer(width: 14, height: 12)
        let first = MediaFrame(pixelBuffer: firstBuffer, metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1))
        let second = MediaFrame(pixelBuffer: secondBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30), frameIndex: 2))
        let sink = PreviewSink { _, _ in }
        var completionResults: [Bool] = []

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink failure: \(error)")
            }
        }
        XCTAssertEqual(sink.state, .active)

        sink.cancel()
        XCTAssertEqual(sink.state, .cancelled)

        sink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected cancelled preview sink failure: \(error)")
            }
            completionResults.append(true)
        }

        XCTAssertEqual(sink.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(sink.lastImage?.width, 10)
        XCTAssertEqual(sink.summary.state, .cancelled)
        XCTAssertFalse(sink.summary.hasPendingFrame)

        sink.resume()
        XCTAssertEqual(sink.state, .cancelled)

        sink.finish { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected preview sink finish failure: \(error)")
            }
            completionResults.append(true)
        }

        XCTAssertEqual(sink.state, .cancelled)
        XCTAssertEqual(completionResults.count, 2)
        XCTAssertEqual(sink.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(sink.lastImage?.width, 10)
    }

    func testPreviewPipelineRoutesFramesThroughPreviewSinkAndSummarizesBoardState() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let frame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let source = SnapshotSource(
            frames: [frame],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                lastFrameIndex: 9,
                lastPresentationTime: .zero,
                lastSourceTime: .zero,
                details: ["board": "preview"]
            )
        )
        let completion = expectation(description: "preview pipeline completion")
        let previewFrames = expectation(description: "preview frame delivered")
        var receivedPreviewMetadata: FrameMetadata?
        let pipeline = PreviewPipeline(source: source) { _, metadata in
            receivedPreviewMetadata = metadata
            previewFrames.fulfill()
        }

        pipeline.pipeline.completionHandler = {
            completion.fulfill()
        }

        pipeline.start()

        wait(for: [previewFrames, completion], timeout: 1)

        XCTAssertEqual(pipeline.state, .finished)
        XCTAssertEqual(pipeline.previewSink.state, .finished)
        XCTAssertEqual(pipeline.summary.sourceTypeName, "SnapshotSource")
        XCTAssertEqual(pipeline.summary.processorCount, 0)
        XCTAssertEqual(pipeline.summary.previewState, .finished)
        XCTAssertEqual(pipeline.summary.lastFrameIndex, 1)
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.details["board"], "preview")
        XCTAssertEqual(receivedPreviewMetadata?.frameIndex, 1)
        XCTAssertTrue(pipeline.summary.summaryText.contains("sourceSnapshot state primed"))
        XCTAssertTrue(pipeline.summary.summaryText.contains("board preview"))
        XCTAssertTrue(pipeline.summary.summaryText.contains("preview finished"))
    }

    func testPreviewPipelineManifestIsCodableForExternalInspection() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let frame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let source = SnapshotSource(
            frames: [frame],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                lastFrameIndex: 9,
                lastPresentationTime: .zero,
                lastSourceTime: .zero,
                details: ["board": "preview"]
            )
        )
        let pipeline = PreviewPipeline(source: source) { _, _ in }
        pipeline.start()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pipeline.manifest)
        let decoded = try JSONDecoder().decode(PreviewPipeline.Manifest.self, from: data)

        XCTAssertEqual(decoded.sourceTypeName, "SnapshotSource")
        XCTAssertEqual(decoded.processorCount, 0)
        XCTAssertEqual(decoded.pipelineStateDescription, "finished")
        XCTAssertEqual(decoded.previewStateDescription, "finished")
        XCTAssertEqual(decoded.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(decoded.sourceSnapshot?.lastFrameIndex, 9)
        XCTAssertEqual(decoded.sourceSnapshot?.lastPresentationTimeSeconds, 0)
        XCTAssertEqual(decoded.sourceSnapshot?.lastSourceTimeSeconds, 0)
        XCTAssertEqual(decoded.sourceSnapshot?.details["board"], "preview")
        XCTAssertEqual(decoded.lastFrameIndex, 1)
        XCTAssertEqual(decoded.lastPresentationTimeSeconds, 0)
        XCTAssertEqual(decoded.lastSourceTimeSeconds, 0)
        XCTAssertEqual(decoded.lastFrameRequestReason, nil)
        XCTAssertEqual(decoded.lastErrorDescription, nil)
    }

    func testPreviewPipelineSummaryIncludesFailureDescriptionFromUnderlyingPipeline() {
        let source = FailingSource(error: NSError(domain: "PreviewPipelineTests", code: 17))
        let pipeline = PreviewPipeline(source: source) { _, _ in }
        let expectation = expectation(description: "preview pipeline failure")

        pipeline.pipeline.errorHandler = { error in
            XCTAssertEqual((error as NSError).domain, "PreviewPipelineTests")
            expectation.fulfill()
        }

        pipeline.start()

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.lastErrorDescription, "PreviewPipelineTests#17")
        XCTAssertEqual(pipeline.summary.lastErrorDescription, "PreviewPipelineTests#17")
        XCTAssertTrue(pipeline.summary.summaryText.contains("error PreviewPipelineTests#17"))
    }

    #if canImport(UIKit) || os(macOS)
    func testPreviewPipelineAssetInitializerBuildsPlayerFrameSource() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let pipeline = PreviewPipeline(asset: asset) { _, _ in }

        XCTAssertTrue(pipeline.source is PlayerFrameSource)
        XCTAssertNotNil(pipeline.playerSource)
        XCTAssertEqual(pipeline.summary.sourceTypeName, "PlayerFrameSource")
        XCTAssertNotNil(pipeline.sourceSnapshot)
        XCTAssertEqual(pipeline.sourceSnapshot?.details["generation"], "0")
    }

    func testPreviewPipelineExposesPlayerSourceStateSnapshot() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let previewExpectation = expectation(description: "preview frame emitted")
        var receivedFrameIndex: Int64?
        let pipeline = PreviewPipeline(source: source) { _, metadata in
            receivedFrameIndex = metadata.frameIndex
            previewExpectation.fulfill()
        }

        pipeline.start()

        XCTAssertEqual(pipeline.playerSourceState, .active)
        XCTAssertEqual(pipeline.playerSourceGeneration, 1)
        XCTAssertEqual(pipeline.playerSourceFrameIndex, 0)
        XCTAssertEqual(pipeline.sourceSnapshot?.details["generation"], "1")
        XCTAssertEqual(pipeline.sourceSnapshot?.details["reason"], "playback")

        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 2, timescale: 30),
                playerTimestamp: CMTime(value: 2, timescale: 30),
                requestTimestamp: CMTime(value: 2, timescale: 30),
                pixelBuffer: try makePixelBuffer(width: 18, height: 12)
            )
        )

        wait(for: [previewExpectation], timeout: 1)
        XCTAssertEqual(receivedFrameIndex, 1)
        XCTAssertEqual(pipeline.playerSourceState, .active)
        XCTAssertEqual(pipeline.playerSourceGeneration, 1)
        XCTAssertEqual(pipeline.playerSourceFrameIndex, 1)
        XCTAssertEqual(pipeline.summary.playerSourceState, .active)
        XCTAssertEqual(pipeline.summary.playerSourceGeneration, 1)
        XCTAssertEqual(pipeline.summary.playerSourceFrameIndex, 1)
        XCTAssertEqual(pipeline.summary.playerSourceLastFrameRequestReason, "manual")
        XCTAssertEqual(pipeline.sourceSnapshot?.details["generation"], "1")
    }

    func testPreviewPipelinePlayerSourceSnapshotExposesUnderlyingPlayerState() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let pipeline = PreviewPipeline(source: source) { _, _ in }

        pipeline.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 2, timescale: 30),
                playerTimestamp: CMTime(value: 2, timescale: 30),
                requestTimestamp: CMTime(value: 2, timescale: 30),
                pixelBuffer: try makePixelBuffer(width: 18, height: 12)
            )
        )

        let snapshot = try XCTUnwrap(pipeline.playerSourceSnapshot)
        XCTAssertEqual(snapshot.state, .active)
        XCTAssertEqual(snapshot.generation, 1)
        XCTAssertEqual(snapshot.frameIndex, 1)
        XCTAssertEqual(snapshot.lastFrameRequestReason, "manual")
        XCTAssertEqual(pipeline.playerSourceState, snapshot.state)
        XCTAssertEqual(pipeline.playerSourceGeneration, snapshot.generation)
        XCTAssertEqual(pipeline.playerSourceFrameIndex, snapshot.frameIndex)
        XCTAssertEqual(pipeline.summary.playerSourceState, snapshot.state)
        XCTAssertEqual(pipeline.summary.playerSourceGeneration, snapshot.generation)
        XCTAssertEqual(pipeline.summary.playerSourceFrameIndex, snapshot.frameIndex)
    }

    func testPreviewPipelineSummaryTracksPausedManualFrames() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let pipeline = PreviewPipeline(source: source) { _, _ in }

        pipeline.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: try makePixelBuffer(width: 18, height: 12)
            )
        )

        XCTAssertEqual(pipeline.summary.playerSourceFrameIndex, 1)
        XCTAssertEqual(pipeline.summary.playerSourceLastFrameRequestReason, "manual")

        source.pause()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 1, timescale: 30),
                playerTimestamp: CMTime(value: 1, timescale: 30),
                requestTimestamp: CMTime(value: 1, timescale: 30),
                pixelBuffer: try makePixelBuffer(width: 18, height: 12)
            )
        )

        XCTAssertEqual(pipeline.summary.playerSourceState, .paused)
        XCTAssertEqual(pipeline.summary.playerSourceGeneration, 1)
        XCTAssertEqual(pipeline.summary.playerSourceFrameIndex, 2)
        XCTAssertEqual(pipeline.summary.playerSourceLastFrameRequestReason, "manual")
    }
    #endif

    #if canImport(UIKit) || os(macOS)
    func testPlayerFrameSourceSummaryReflectsPlaybackAndFrameProgress() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let pixelBuffer = try makePixelBuffer(width: 18, height: 12)

        source.start()
        XCTAssertEqual(source.summary.state, .active)
        XCTAssertEqual(source.summary.generation, 1)
        XCTAssertEqual(source.summary.frameIndex, 0)
        XCTAssertEqual(source.sourceSnapshot.details["generation"], "1")
        XCTAssertEqual(source.sourceSnapshot.details["reason"], "playback")
        XCTAssertEqual(source.summary.hasLastFrame, false)
        XCTAssertTrue(source.summary.summaryText.contains("state active · generation 1 · frame 0 · lastFrame no · seekTarget no · fps 30"))
        XCTAssertTrue(source.summaryText.contains("sourceSnapshot state active"))
        XCTAssertTrue(source.summaryText.contains("generation 1"))
        XCTAssertTrue(source.summaryText.contains("reason playback"))
        XCTAssertTrue(source.summaryText.contains("playerRate 0.00"))
        XCTAssertTrue(source.summaryText.contains("playbackState running"))
        XCTAssertTrue(source.summaryText.contains("seekTarget no"))

        source.pause()
        XCTAssertEqual(source.summary.state, .paused)

        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: pixelBuffer
            )
        )

        XCTAssertEqual(source.summary.frameIndex, 1)
        XCTAssertEqual(source.summary.hasLastFrame, true)
        XCTAssertEqual(source.summary.lastFrameRequestReason, "manual")
        XCTAssertEqual(source.summary.lastPresentationTime, .zero)
        XCTAssertEqual(source.summary.lastPlayerItemTime, .zero)
        XCTAssertTrue(source.summary.summaryText.contains("state paused · generation 1 · frame 1"))
        XCTAssertTrue(source.summary.summaryText.contains("lastFrame yes"))
        XCTAssertTrue(source.summary.summaryText.contains("reason manual"))
        XCTAssertTrue(source.summary.summaryText.contains("presentation 0.00s"))
        XCTAssertTrue(source.summary.summaryText.contains("itemTime 0.00s"))
        XCTAssertTrue(source.summaryText.contains("sourceSnapshot state paused"))
        XCTAssertTrue(source.summaryText.contains("sourceTime 0.00s"))
        XCTAssertTrue(source.summaryText.contains("itemTime 0.00s"))
    }
    #endif

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

    func testMediaPipelineStopInvokesUpstreamStopOnlyOnceAfterTerminalState() {
        let source = CountingStopSource()
        let sink = CountingSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])

        pipeline.stop()
        pipeline.stop()

        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(pipeline.state, .finished)
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

    func testMediaPipelineTracksRunningPausedFinishedAndFailedStates() {
        let successSource = TestSource(frames: [])
        let successPipeline = MediaPipeline(source: successSource, processors: [], sinks: [])
        let successExpectation = expectation(description: "success state callbacks")
        successExpectation.expectedFulfillmentCount = 2
        var successStates: [MediaPipeline.State] = []
        successPipeline.stateHandler = { state in
            successStates.append(state)
            successExpectation.fulfill()
        }

        successPipeline.start()
        wait(for: [successExpectation], timeout: 1)

        XCTAssertEqual(successStates, [.running, .finished])
        XCTAssertEqual(successPipeline.state, .finished)

        let failureSource = FailingSource(error: NSError(domain: "MediaPipelineTests", code: 11))
        let failurePipeline = MediaPipeline(source: failureSource, processors: [], sinks: [])
        let failureExpectation = expectation(description: "failure state callbacks")
        failureExpectation.expectedFulfillmentCount = 2
        let errorExpectation = expectation(description: "failure error callback")
        var failureStates: [MediaPipeline.State] = []
        var receivedError: NSError?

        failurePipeline.stateHandler = { state in
            failureStates.append(state)
            failureExpectation.fulfill()
        }
        failurePipeline.errorHandler = { error in
            receivedError = error as NSError
            errorExpectation.fulfill()
        }

        failurePipeline.start()

        wait(for: [failureExpectation, errorExpectation], timeout: 1)

        XCTAssertEqual(failureStates, [.running, .failed])
        XCTAssertEqual(receivedError?.domain, "MediaPipelineTests")
        XCTAssertEqual(receivedError?.code, 11)
        XCTAssertEqual(failurePipeline.state, .failed)
        XCTAssertEqual(failurePipeline.lastErrorDescription, "MediaPipelineTests#11")
        XCTAssertEqual(
            failurePipeline.summary.summaryText,
            "source FailingSource · processors 0 · sinks 0 · state failed · error MediaPipelineTests#11"
        )
    }

    func testMediaPipelineRestartClearsStaleFailureAndFrameMetadata() throws {
        let firstFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 12, height: 10),
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let secondFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 16, height: 12),
            metadata: FrameMetadata(
                presentationTime: CMTime(value: 1, timescale: 30),
                sourceTime: CMTime(value: 1, timescale: 30),
                frameIndex: 2
            )
        )
        let source = SequencedSource(runs: [
            [.output(firstFrame), .fail(NSError(domain: "MediaPipelineRestartTests", code: 91))],
            [.output(secondFrame), .finish]
        ])
        let sink = TestSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])

        pipeline.start()

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.lastFrameMetadata?.frameIndex, 1)
        XCTAssertEqual(pipeline.lastErrorDescription, "MediaPipelineRestartTests#91")

        pipeline.start()

        XCTAssertEqual(pipeline.state, .finished)
        XCTAssertEqual(pipeline.lastFrameMetadata?.frameIndex, 2)
        XCTAssertNil(pipeline.lastErrorDescription)
        XCTAssertEqual(sink.frames.count, 2)
        XCTAssertEqual(
            pipeline.summary.summaryText,
            "source SequencedSource · processors 0 · sinks 1 · state finished · frame 2 · presentation 0.03s · sourceTime 0.03s"
        )
    }

    func testMediaPipelineSurfacesSinkFinishFailuresAfterSourceCompletion() {
        let source = TestSource(frames: [])
        let sinkError = NSError(domain: "MediaPipelineTests", code: 29)
        let sink = FailingFinishSink(error: sinkError)
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])

        let stateExpectation = expectation(description: "terminal state callbacks")
        stateExpectation.expectedFulfillmentCount = 3
        let errorExpectation = expectation(description: "finish failure error callback")
        var states: [MediaPipeline.State] = []
        var receivedError: NSError?

        pipeline.stateHandler = { state in
            states.append(state)
            stateExpectation.fulfill()
        }
        pipeline.errorHandler = { error in
            receivedError = error as NSError
            errorExpectation.fulfill()
        }

        pipeline.start()

        wait(for: [stateExpectation, errorExpectation], timeout: 1)

        XCTAssertEqual(states, [.running, .finished, .failed])
        XCTAssertEqual(receivedError?.domain, "MediaPipelineTests")
        XCTAssertEqual(receivedError?.code, 29)
        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.lastErrorDescription, "MediaPipelineTests#29")
        XCTAssertEqual(
            pipeline.summary.summaryText,
            "source TestSource · processors 0 · sinks 1 · state failed · error MediaPipelineTests#29"
        )
    }

    func testMediaPipelineIgnoresLateSourceCallbacksAfterFinish() throws {
        let source = ManualSource()
        let sink = TestSink()
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])
        let initialFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 8, height: 8),
            metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1)
        )
        let lateFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 8, height: 8),
            metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30), frameIndex: 2)
        )

        pipeline.start()
        source.emit(initialFrame)
        source.finish()

        XCTAssertEqual(pipeline.state, .finished)
        XCTAssertEqual(sink.frames.count, 1)
        XCTAssertEqual(pipeline.lastFrameMetadata?.frameIndex, 1)

        source.emit(lateFrame)
        source.finish()
        source.fail(NSError(domain: "MediaPipelineTests", code: 999))

        XCTAssertEqual(pipeline.state, .finished)
        XCTAssertEqual(sink.frames.count, 1)
        XCTAssertEqual(pipeline.lastFrameMetadata?.frameIndex, 1)
        XCTAssertNil(pipeline.lastErrorDescription)
    }

    func testMediaPipelineCancelsUpstreamSourceWhenSinkFailsDuringStreaming() throws {
        let firstFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 8, height: 8),
            metadata: FrameMetadata(presentationTime: .zero, frameIndex: 1)
        )
        let secondFrame = MediaFrame(
            pixelBuffer: try makePixelBuffer(width: 8, height: 8),
            metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30), frameIndex: 2)
        )
        let source = DelayedEmittingSource(frames: [firstFrame, secondFrame], emissionDelay: 0.15)
        let sink = FailingConsumeSink(error: NSError(domain: "MediaPipelineTests", code: 41))
        let pipeline = MediaPipeline(source: source, processors: [], sinks: [sink])
        let errorExpectation = expectation(description: "pipeline failure")
        let stateExpectation = expectation(description: "failed state")
        stateExpectation.expectedFulfillmentCount = 2

        pipeline.errorHandler = { error in
            XCTAssertEqual((error as NSError).code, 41)
            errorExpectation.fulfill()
        }
        pipeline.stateHandler = { state in
            if state == .running || state == .failed {
                stateExpectation.fulfill()
            }
        }

        pipeline.start()

        wait(for: [errorExpectation, stateExpectation], timeout: 2)

        XCTAssertEqual(source.cancelCount, 1)
        XCTAssertEqual(source.emissionCount, 1)
        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.lastErrorDescription, "MediaPipelineTests#41")
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

    func testPlayerFrameCoordinatorResetsFrameIndexWhenRestartingSameItem() {
        final class Token: NSObject {}

        var coordinator = PlayerFrameCoordinator()
        let token = Token()

        XCTAssertTrue(coordinator.start(with: token))
        XCTAssertEqual(coordinator.generation, 1)
        XCTAssertEqual(coordinator.markFrameOutput(), 1)
        XCTAssertEqual(coordinator.markFrameOutput(), 2)

        XCTAssertTrue(coordinator.start(with: token))
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

    #if canImport(UIKit) || os(macOS)
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

        XCTAssertEqual(driver.setNeedsUpdateCallCount, 2)
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

    func testPlayerFrameSourceSnapshotMirrorsSummaryAndSourceSnapshotState() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 4, timescale: 30),
                playerTimestamp: CMTime(value: 4, timescale: 30),
                requestTimestamp: CMTime(value: 5, timescale: 30),
                pixelBuffer: try makePixelBuffer(width: 18, height: 12)
            )
        )

        let snapshot = source.snapshot
        XCTAssertEqual(snapshot.state, .active)
        XCTAssertEqual(snapshot.generation, 1)
        XCTAssertEqual(snapshot.frameIndex, 1)
        XCTAssertTrue(snapshot.hasLastFrame)
        XCTAssertFalse(snapshot.hasSeekTarget)
        XCTAssertEqual(snapshot.lastFrameRequestReason, "manual")
        XCTAssertEqual(snapshot.lastPresentationTime, CMTime(value: 4, timescale: 30))
        XCTAssertEqual(snapshot.lastPlayerItemTime, CMTime(value: 5, timescale: 30))
        XCTAssertEqual(snapshot.preferredFramesPerSecond, 30)
        XCTAssertNil(snapshot.lastErrorDescription)
        XCTAssertEqual(source.summary.state, snapshot.state)
        XCTAssertEqual(source.summary.generation, snapshot.generation)
        XCTAssertEqual(source.summary.frameIndex, snapshot.frameIndex)
        XCTAssertEqual(source.sourceSnapshot.details["generation"], "1")
        XCTAssertEqual(source.sourceSnapshot.details["reason"], "manual")
        XCTAssertTrue(source.summaryText.contains("sourceSnapshot state active"))
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

    func testPlayerFrameSourceSeekClearsStaleFrameAndTagsNextFrameAsSeek() throws {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL())))
        let driver = FakePlayerFrameDriver()
        let seekExpectation = expectation(description: "seek completed")
        let frameExpectation = expectation(description: "seek frame emitted")
        frameExpectation.expectedFulfillmentCount = 2
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let initialBuffer = try makePixelBuffer(width: 16, height: 10)
        let seekBuffer = try makePixelBuffer(width: 22, height: 16)
        let target = CMTime(value: 24, timescale: 30)
        var receivedFrame: MediaFrame?

        source.frameHandler = { frame in
            receivedFrame = frame
            frameExpectation.fulfill()
        }

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: initialBuffer
            )
        )

        XCTAssertNotNil(source.lastFrame)

        source.seek(to: target) { finished in
            XCTAssertTrue(finished)
            seekExpectation.fulfill()
        }

        wait(for: [seekExpectation], timeout: 5)
        XCTAssertNil(source.lastFrame)
        XCTAssertEqual(source.lastSeekTargetTime, target)

        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: target,
                playerTimestamp: target,
                requestTimestamp: target,
                pixelBuffer: seekBuffer
            )
        )

        wait(for: [frameExpectation], timeout: 1)
        XCTAssertEqual(receivedFrame?.metadata.userInfo[PlayerFrameSource.MetadataKey.frameRequestReason] as? String, "seek")
        XCTAssertEqual(receivedFrame?.metadata.userInfo[PlayerFrameSource.MetadataKey.seekTargetTime] as? CMTime, target)
        XCTAssertNil(source.lastSeekTargetTime)
        XCTAssertEqual(source.lastFrame?.metadata.frameIndex, 2)
        XCTAssertEqual(CVPixelBufferGetWidth(try XCTUnwrap(source.lastFrame?.pixelBuffer)), 22)
        XCTAssertEqual(source.summary.lastFrameRequestReason, "seek")
        XCTAssertEqual(source.summary.lastPresentationTime, target)
        XCTAssertEqual(source.summary.lastPlayerItemTime, target)
        XCTAssertTrue(source.summary.summaryText.contains("reason seek"))
        XCTAssertTrue(source.summaryText.contains("seekTarget no"))
        XCTAssertTrue(source.sourceSnapshot.details["seekTargetTime"] == "n/a")
    }

    func testPlayerFrameSourceResetsSeekTargetAndLastFrameWhenCurrentItemChanges() throws {
        let firstItem = AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL()))
        let secondItem = AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL()))
        let player = AVPlayer(playerItem: firstItem)
        let driver = FakePlayerFrameDriver()
        let itemExpectation = expectation(description: "current item changed")
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let pixelBuffer = try makePixelBuffer(width: 20, height: 14)
        let target = CMTime(value: 30, timescale: 30)
        var observedItems: [AVPlayerItem?] = []

        source.itemChangedHandler = { item in
            observedItems.append(item)
            if item === secondItem {
                itemExpectation.fulfill()
            }
        }

        source.start()
        source.seek(to: target) { _ in }
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: pixelBuffer
            )
        )

        XCTAssertEqual(source.lastSeekTargetTime, target)
        XCTAssertNotNil(source.lastFrame)

        player.replaceCurrentItem(with: secondItem)

        wait(for: [itemExpectation], timeout: 1)
        XCTAssertEqual(observedItems.compactMap { $0 }, [firstItem, secondItem])
        XCTAssertNil(source.lastSeekTargetTime)
        XCTAssertNil(source.lastFrame)
    }

    func testPlayerFrameSourceRestartClearsStaleFrameAndStartsNewGeneration() throws {
        let item = AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL()))
        let player = AVPlayer(playerItem: item)
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let firstBuffer = try makePixelBuffer(width: 18, height: 12)
        let secondBuffer = try makePixelBuffer(width: 24, height: 16)
        let firstFrameExpectation = expectation(description: "first frame emitted")
        let secondFrameExpectation = expectation(description: "second frame emitted after restart")
        var receivedGenerationValues: [Int64] = []

        source.frameHandler = { frame in
            if let generation = frame.metadata.userInfo[PlayerFrameSource.MetadataKey.generation] as? Int64 {
                receivedGenerationValues.append(generation)
            }
            if receivedGenerationValues.count == 1 {
                firstFrameExpectation.fulfill()
            } else if receivedGenerationValues.count == 2 {
                secondFrameExpectation.fulfill()
            }
        }

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: firstBuffer
            )
        )

        wait(for: [firstFrameExpectation], timeout: 1)
        XCTAssertEqual(source.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(receivedGenerationValues, [1])

        source.stop()
        XCTAssertEqual(source.state, .finished)

        source.start()
        XCTAssertNil(source.lastFrame)
        XCTAssertEqual(source.state, .active)

        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 1, timescale: 30),
                playerTimestamp: CMTime(value: 1, timescale: 30),
                requestTimestamp: CMTime(value: 1, timescale: 30),
                pixelBuffer: secondBuffer
            )
        )

        wait(for: [secondFrameExpectation], timeout: 1)
        XCTAssertEqual(source.lastFrame?.metadata.frameIndex, 1)
        XCTAssertEqual(receivedGenerationValues, [1, 2])
    }

    func testPlayerFrameSourceIgnoresLateFramesAfterStopAndCancel() throws {
        let item = AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL()))
        let player = AVPlayer(playerItem: item)
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        let firstBuffer = try makePixelBuffer(width: 18, height: 12)
        let secondBuffer = try makePixelBuffer(width: 24, height: 16)
        var receivedFrames: [MediaFrame] = []

        source.frameHandler = { frame in
            receivedFrames.append(frame)
        }

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: .zero,
                playerTimestamp: .zero,
                requestTimestamp: .zero,
                pixelBuffer: firstBuffer
            )
        )

        XCTAssertEqual(receivedFrames.count, 1)
        XCTAssertEqual(receivedFrames[0].metadata.frameIndex, 1)

        source.stop()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 1, timescale: 30),
                playerTimestamp: CMTime(value: 1, timescale: 30),
                requestTimestamp: CMTime(value: 1, timescale: 30),
                pixelBuffer: secondBuffer
            )
        )
        XCTAssertEqual(receivedFrames.count, 1)

        source.start()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 2, timescale: 30),
                playerTimestamp: CMTime(value: 2, timescale: 30),
                requestTimestamp: CMTime(value: 2, timescale: 30),
                pixelBuffer: secondBuffer
            )
        )
        XCTAssertEqual(receivedFrames.count, 2)
        XCTAssertEqual(receivedFrames[1].metadata.frameIndex, 1)

        source.cancel()
        driver.emitFrame(
            .init(
                preferredTrackTransform: .identity,
                presentationTimestamp: CMTime(value: 3, timescale: 30),
                playerTimestamp: CMTime(value: 3, timescale: 30),
                requestTimestamp: CMTime(value: 3, timescale: 30),
                pixelBuffer: secondBuffer
            )
        )
        XCTAssertEqual(receivedFrames.count, 2)
    }

    func testPlayerFrameSourceSurfacesItemFailureToDelegateAndSummary() throws {
        let item = AVPlayerItem(asset: AVAsset(url: try makeSampleAssetURL()))
        let player = AVPlayer(playerItem: item)
        let driver = FakePlayerFrameDriver()
        let source = PlayerFrameSource(
            player: player,
            driverFactory: { _, configuration, handler in
                driver.configuration = configuration
                driver.frameHandler = handler
                return driver
            }
        )
        final class DelegateSpy: MediaSourceDelegate {
            var didFailError: NSError?
            var didFinishCount = 0

            func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame) {}

            func mediaSource(_ source: MediaSource, didFail error: Error) {
                didFailError = error as NSError
            }

            func mediaSourceDidFinish(_ source: MediaSource) {
                didFinishCount += 1
            }
        }

        let spy = DelegateSpy()
        source.delegate = spy
        let stateExpectation = expectation(description: "player failure finished")
        source.stateChangedHandler = { state in
            if state == .finished {
                stateExpectation.fulfill()
            }
        }

        source.start()
        let error = NSError(domain: "PlayerFrameSourceTests", code: 77)
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error]
        )

        wait(for: [stateExpectation], timeout: 1)
        XCTAssertEqual(source.state, .finished)
        XCTAssertEqual(source.lastErrorDescription, "PlayerFrameSourceTests#77")
        XCTAssertEqual(source.summary.lastErrorDescription, "PlayerFrameSourceTests#77")
        XCTAssertTrue(source.summary.summaryText.contains("error PlayerFrameSourceTests#77"))
        XCTAssertEqual(spy.didFailError?.domain, "PlayerFrameSourceTests")
        XCTAssertEqual(spy.didFailError?.code, 77)
        XCTAssertEqual(spy.didFinishCount, 0)
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
        XCTAssertTrue(recordedClip?.fileExists == true)
        XCTAssertNotNil(recordedClip?.asset)
        XCTAssertEqual(recordedClip?.segments.first?.containsVideo, true)
        XCTAssertEqual(recordedClip?.segments.first?.containsAudio, false)
        XCTAssertEqual(recordedClip?.representationDictionary?[RecordedClipFilenameKey] as? String, outputURL.lastPathComponent)
        XCTAssertEqual(recordedClip?.mergeHandoff.segmentCount, 1)
        XCTAssertEqual(recordedClip?.mergeHandoff.containsVideo, true)
        XCTAssertEqual(recordedClip?.mergeHandoff.containsAudio, false)
        XCTAssertEqual(recordedClip?.normalizedSessionManifest["containsVideo"], "true")
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
        XCTAssertEqual(recordedClip?.segments.allSatisfy(\.containsVideo), true)
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
        XCTAssertEqual(recordedClip?.segments.last?.containsVideo, true)
    }

    func testRecordedClipRepresentationCanRoundTripAndRemoveBackingFile() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let outputURL = directoryURL.appendingPathComponent("segment").appendingPathExtension("mp4")
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("kakapos".utf8))

        let clip = RecordedClip(
            outputURL: outputURL,
            duration: CMTime(value: 3, timescale: 30),
            startedAt: .zero,
            endedAt: CMTime(value: 3, timescale: 30),
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: CMTime(value: 3, timescale: 30),
                    duration: CMTime(value: 3, timescale: 30),
                    containsVideo: true,
                    containsAudio: true
                )
            ],
            infoDictionary: ["origin": "unit-test"]
        )

        XCTAssertTrue(clip.fileExists)
        XCTAssertEqual(clip.representationDictionary?[RecordedClipFilenameKey] as? String, outputURL.lastPathComponent)
        XCTAssertEqual((clip.representationDictionary?[RecordedClipInfoDictionaryKey] as? [String: String])?["origin"], "unit-test")
        XCTAssertEqual(clip.mergeHandoff.segmentCount, 1)
        XCTAssertEqual(clip.mergeHandoff.containsVideo, true)
        XCTAssertEqual(clip.mergeHandoff.containsAudio, true)
        XCTAssertTrue(clip.summaryText.contains("segments 1"))

        let restored = RecordedClip(directoryPath: directoryURL.path, representationDictionary: clip.representationDictionary)
        XCTAssertEqual(restored.outputURL, outputURL)
        XCTAssertTrue(restored.fileExists)
        XCTAssertEqual((restored.infoDictionary as? [String: String])?["origin"], "unit-test")

        restored.removeFile()
        XCTAssertNil(restored.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testRecordedClipCanBuildAssetSourceAndPreserveMergeMetadata() throws {
        let outputURL = try makeSampleAssetURL()
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: CMTime(value: 30, timescale: 30),
            startedAt: .zero,
            endedAt: CMTime(value: 30, timescale: 30),
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: CMTime(value: 30, timescale: 30),
                    duration: CMTime(value: 30, timescale: 30),
                    containsVideo: true,
                    containsAudio: true
                )
            ],
            isMutedOnMerge: true,
            sessionManifest: ["origin": "camera", "clipCount": 1]
        )
        let source = try XCTUnwrap(AssetSource(recordedClip: clip))

        XCTAssertEqual((source.asset as? AVURLAsset)?.url, outputURL)
        XCTAssertEqual(source.frameUserInfo[AssetSource.MetadataKey.recordedClipIdentifier] as? String, clip.identifier.uuidString)
        XCTAssertEqual(source.frameUserInfo[AssetSource.MetadataKey.recordedClipSegmentCount] as? Int, 1)
        XCTAssertEqual(source.frameUserInfo[AssetSource.MetadataKey.recordedClipContainsVideo] as? Bool, true)
        XCTAssertEqual(source.frameUserInfo[AssetSource.MetadataKey.recordedClipContainsAudio] as? Bool, true)
        XCTAssertEqual(source.frameUserInfo[AssetSource.MetadataKey.recordedClipMutedOnMerge] as? Bool, true)
        XCTAssertEqual(source.frameUserInfo["origin"] as? String, "camera")
        XCTAssertEqual(source.frameUserInfo["clipCount"] as? String, "1")
    }

    func testRecordedClipCanBuildTimelinePipelineAndMutedClipLayer() throws {
        let outputURL = try makeSampleAssetURL()
        let duration = CMTime(value: 30, timescale: 30)
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: .zero,
            endedAt: duration,
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: duration,
                    duration: duration,
                    containsVideo: true,
                    containsAudio: true
                )
            ],
            isMutedOnMerge: true
        )

        let layer = try XCTUnwrap(ClipLayer(recordedClip: clip))
        let pipeline = try XCTUnwrap(TimelinePipeline(recordedClip: clip))
        let compiled = pipeline.compile()

        XCTAssertEqual(layer.volume, 0)
        XCTAssertEqual(layer.timeRange.duration, duration)
        XCTAssertEqual(pipeline.layers.count, 1)
        XCTAssertEqual(compiled.summary.videoLayerCount, 1)
        XCTAssertEqual(compiled.summary.transitionCount, 0)
    }

    #if canImport(UIKit) || os(macOS)
    func testRecordedClipCanBuildPlayerAndPreviewBridges() throws {
        let outputURL = try makeSampleAssetURL()
        let duration = CMTime(value: 30, timescale: 30)
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: .zero,
            endedAt: duration,
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: duration,
                    duration: duration,
                    containsVideo: true,
                    containsAudio: true
                )
            ]
        )

        let playerItem = try XCTUnwrap(clip.makePlayerItem())
        let playerSource = try XCTUnwrap(clip.makePlayerFrameSource(preferredFramesPerSecond: 24))
        let previewPipeline = try XCTUnwrap(clip.makePreviewPipeline(preferredFramesPerSecond: 24) { _, _ in })

        XCTAssertEqual((playerItem.asset as? AVURLAsset)?.url, outputURL)
        XCTAssertEqual(playerSource.preferredFramesPerSecond, 24)
        XCTAssertEqual(previewPipeline.playerSource?.preferredFramesPerSecond, 24)
        XCTAssertEqual(previewPipeline.summary.sourceTypeName, "PlayerFrameSource")
    }
    #endif

    func testRecordedClipCanBuildExportJobAndTaskThroughTimelineBridge() throws {
        let outputURL = try makeSampleAssetURL()
        let duration = CMTime(value: 30, timescale: 30)
        let clip = RecordedClip(
            outputURL: outputURL,
            duration: duration,
            startedAt: .zero,
            endedAt: duration,
            segments: [
                RecordedClipSegment(
                    index: 0,
                    startedAt: .zero,
                    endedAt: duration,
                    duration: duration,
                    containsVideo: true,
                    containsAudio: true
                )
            ],
            isMutedOnMerge: true
        )
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let job = try XCTUnwrap(clip.makeExportJob(outputURL: exportURL))
        let task = try XCTUnwrap(clip.makeExportTask(outputURL: exportURL))

        XCTAssertEqual(job.summary.status, .idle)
        XCTAssertEqual(task.status, .idle)
        XCTAssertTrue(job.summary.summaryText.contains("state idle"))
        XCTAssertTrue(task.summary.compiledSummary.videoLayerCount == 1)
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

    func testRecorderSinkCancelRemovesPartialOutputFile() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let appendExpectation = expectation(description: "append frame before cancel")
        let cancelExpectation = expectation(description: "cancel state callback")

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        sink.stateChangedHandler = { state in
            if state == .cancelled {
                cancelExpectation.fulfill()
            }
        }
        sink.cancel()

        wait(for: [cancelExpectation], timeout: 5)
        XCTAssertEqual(sink.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertNil(sink.recordedClip)
    }

    func testRecorderSinkSnapshotTracksMaximumDurationAndRemainingDuration() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        sink.maximumDuration = CMTime(seconds: 2, preferredTimescale: 600)
        let pixelBuffer = try makePixelBuffer(width: 16, height: 16)
        let frame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(seconds: 0.5, preferredTimescale: 600))
        )
        let appendExpectation = expectation(description: "append limited frame")

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)
        let snapshot = sink.snapshot
        XCTAssertEqual(snapshot.maximumDuration, CMTime(seconds: 2, preferredTimescale: 600))
        XCTAssertEqual(snapshot.containsVideo, true)
        XCTAssertEqual(snapshot.containsAudio, false)
        XCTAssertNotNil(snapshot.remainingDuration)
        XCTAssertTrue(sink.summaryText.contains("max 2.00s"))
        XCTAssertTrue(sink.summaryText.contains("remaining"))
    }

    func testRecorderSinkIgnoresLateFramesAfterCancelAndFinish() throws {
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: CMTime(value: 1, timescale: 30)))

        let cancelledOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let cancelledSink = try RecorderSink(outputURL: cancelledOutputURL)
        let cancelAppendExpectation = expectation(description: "append before cancel")
        let cancelStateExpectation = expectation(description: "cancel state callback")
        cancelledSink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            cancelAppendExpectation.fulfill()
        }
        wait(for: [cancelAppendExpectation], timeout: 2)
        cancelledSink.stateChangedHandler = { state in
            if state == .cancelled {
                cancelStateExpectation.fulfill()
            }
        }
        cancelledSink.cancel()
        cancelledSink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected cancelled recorder failure: \(error)")
            }
        }
        wait(for: [cancelStateExpectation], timeout: 5)
        XCTAssertEqual(cancelledSink.state, .cancelled)
        XCTAssertNil(cancelledSink.recordedClip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledOutputURL.path))

        let finishedOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let finishedSink = try RecorderSink(outputURL: finishedOutputURL)
        let finishAppendExpectation = expectation(description: "append before finish")
        let finishExpectation = expectation(description: "finish state callback")
        var recordedClip: RecordedClip?
        finishedSink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            finishAppendExpectation.fulfill()
        }
        wait(for: [finishAppendExpectation], timeout: 2)
        finishedSink.finishRecording { result in
            switch result {
            case .success(let clip):
                recordedClip = clip
            case .failure(let error):
                XCTFail("Unexpected finish recording failure: \(error)")
            }
            finishExpectation.fulfill()
        }
        finishedSink.consume(second) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected finished recorder failure: \(error)")
            }
        }
        wait(for: [finishExpectation], timeout: 5)
        XCTAssertEqual(finishedSink.state, .finished)
        XCTAssertEqual(recordedClip?.startedAt, .zero)
        XCTAssertEqual(recordedClip?.endedAt, CMTime(value: 1, timescale: 600))
        XCTAssertEqual(recordedClip?.duration, CMTime(value: 1, timescale: 600))
        XCTAssertTrue(recordedClip?.fileExists == true)
    }

    func testRecorderSinkSnapshotTracksActiveSegmentAndPausedState() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let firstFrame = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let appendExpectation = expectation(description: "append frame for snapshot")

        sink.consume(firstFrame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        wait(for: [appendExpectation], timeout: 2)

        let recordingSnapshot = sink.snapshot
        XCTAssertEqual(recordingSnapshot.state, .recording)
        XCTAssertEqual(recordingSnapshot.outputURL, outputURL)
        XCTAssertTrue(recordingSnapshot.currentClipHasStarted)
        XCTAssertTrue(recordingSnapshot.currentClipHasVideo)
        XCTAssertFalse(recordingSnapshot.currentClipHasAudio)
        XCTAssertEqual(recordingSnapshot.clipCount, 0)
        XCTAssertEqual(recordingSnapshot.recordedVideoSegmentCount, 0)
        XCTAssertEqual(recordingSnapshot.recordedAudioSegmentCount, 0)
        XCTAssertFalse(recordingSnapshot.hasRecordedClip)

        sink.pauseRecording(at: CMTime(value: 30, timescale: 30))
        let pausedSnapshot = sink.snapshot
        XCTAssertEqual(pausedSnapshot.state, .paused)
        XCTAssertNotNil(pausedSnapshot.pausedAt)
        XCTAssertEqual(pausedSnapshot.clipCount, 1)
        XCTAssertGreaterThanOrEqual(pausedSnapshot.totalDuration.seconds, 0)
        XCTAssertGreaterThanOrEqual(pausedSnapshot.currentClipDuration.seconds, 0)
    }

    func testRecorderSinkSummaryReflectsRecordedDurationAndClipCounts() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let frame = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let expectedClipDuration = CMTime(value: 1, timescale: 600)
        let expectation = self.expectation(description: "append frame for summary")

        sink.consume(frame) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(sink.summary.state, .recording)
        XCTAssertEqual(sink.summary.outputURL, outputURL)
        XCTAssertEqual(sink.summary.clipCount, 0)
        XCTAssertEqual(sink.summary.totalDuration, .zero)
        XCTAssertEqual(sink.summary.currentClipDuration, expectedClipDuration)
        XCTAssertEqual(sink.summary.hasRecordedClip, false)
        XCTAssertTrue(sink.summary.currentClipHasStarted)
        XCTAssertTrue(sink.summary.currentClipHasVideo)
        XCTAssertFalse(sink.summary.currentClipHasAudio)
        XCTAssertEqual(sink.summary.recordedVideoSegmentCount, 0)
        XCTAssertEqual(sink.summary.recordedAudioSegmentCount, 0)
        XCTAssertEqual(sink.summary.lastPresentationTime, .zero)
        XCTAssertNil(sink.summary.pausedAt)
        XCTAssertTrue(sink.summary.summaryText.contains("state recording"))
        XCTAssertTrue(sink.summary.summaryText.contains("segments v0/a0"))
        XCTAssertTrue(sink.summary.summaryText.contains("payload vyes/ano"))
        XCTAssertTrue(sink.summary.summaryText.contains("presentation 0.00s"))
    }

    func testRecordingPipelineRoutesFramesToRecorderAndSummarizesBoardState() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let frame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let source = SnapshotSource(
            frames: [frame],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                lastFrameIndex: 9,
                lastPresentationTime: .zero,
                lastSourceTime: .zero,
                details: ["board": "record"]
            )
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let pipeline = try RecordingPipeline(source: source, outputURL: outputURL)
        let completion = expectation(description: "recording pipeline completion")

        pipeline.pipeline.completionHandler = {
            completion.fulfill()
        }

        pipeline.start()

        wait(for: [completion], timeout: 2)

        XCTAssertEqual(pipeline.state, .finished)
        XCTAssertEqual(pipeline.recorderSink.state, .finished)
        XCTAssertEqual(pipeline.summary.sourceTypeName, "SnapshotSource")
        XCTAssertEqual(pipeline.summary.processorCount, 0)
        XCTAssertEqual(pipeline.summary.pipelineState, .finished)
        XCTAssertEqual(pipeline.summary.recorderState, .finished)
        XCTAssertEqual(pipeline.summary.clipCount, 1)
        XCTAssertTrue(pipeline.summary.hasRecordedClip)
        XCTAssertFalse(pipeline.summary.currentClipHasStarted)
        XCTAssertFalse(pipeline.summary.currentClipHasVideo)
        XCTAssertFalse(pipeline.summary.currentClipHasAudio)
        XCTAssertEqual(pipeline.summary.recordedVideoSegmentCount, 1)
        XCTAssertEqual(pipeline.summary.recordedAudioSegmentCount, 0)
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(pipeline.summary.sourceSnapshot?.details["board"], "record")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(pipeline.summaryText.contains("sourceSnapshot state primed"))
        XCTAssertTrue(pipeline.summaryText.contains("board record"))
        XCTAssertTrue(pipeline.summaryText.contains("recorder finished"))
        XCTAssertTrue(pipeline.summaryText.contains("started no"))
        XCTAssertTrue(pipeline.summaryText.contains("segments v1/a0"))
    }

    func testRecordingPipelineManifestIsCodableForExternalInspection() throws {
        let pixelBuffer = try makePixelBuffer(width: 12, height: 10)
        let frame = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: .zero, sourceTime: .zero, frameIndex: 1)
        )
        let source = SnapshotSource(
            frames: [frame],
            snapshot: MediaSourceSnapshot(
                stateDescription: "primed",
                lastFrameIndex: 9,
                lastPresentationTime: .zero,
                lastSourceTime: .zero,
                details: ["board": "record"]
            )
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let pipeline = try RecordingPipeline(source: source, outputURL: outputURL)
        let completion = expectation(description: "recording pipeline completion")

        pipeline.pipeline.completionHandler = {
            completion.fulfill()
        }

        pipeline.start()

        wait(for: [completion], timeout: 2)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pipeline.manifest)
        let decoded = try JSONDecoder().decode(RecordingPipeline.Manifest.self, from: data)

        XCTAssertEqual(decoded.sourceTypeName, "SnapshotSource")
        XCTAssertEqual(decoded.processorCount, 0)
        XCTAssertEqual(decoded.pipelineStateDescription, "finished")
        XCTAssertEqual(decoded.recorderStateDescription, "finished")
        XCTAssertEqual(decoded.sourceSnapshot?.stateDescription, "primed")
        XCTAssertEqual(decoded.sourceSnapshot?.lastFrameIndex, 9)
        XCTAssertEqual(decoded.sourceSnapshot?.details["board"], "record")
        XCTAssertEqual(decoded.recorderSnapshot.stateDescription, "finished")
        XCTAssertEqual(decoded.recorderSnapshot.clipCount, 1)
        XCTAssertEqual(decoded.recorderSnapshot.hasRecordedClip, true)
        XCTAssertEqual(decoded.recorderSnapshot.recordedVideoSegmentCount, 1)
        XCTAssertEqual(decoded.recorderSnapshot.recordedAudioSegmentCount, 0)
        XCTAssertEqual(decoded.clipCount, 1)
        XCTAssertGreaterThanOrEqual(decoded.totalDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(decoded.currentClipDurationSeconds, 0)
        XCTAssertTrue(decoded.hasRecordedClip)
        XCTAssertFalse(decoded.currentClipHasStarted)
        XCTAssertFalse(decoded.currentClipHasVideo)
        XCTAssertFalse(decoded.currentClipHasAudio)
        XCTAssertEqual(decoded.lastErrorDescription, nil)
    }

#if canImport(UIKit) && !os(watchOS)
    func testRecordingPipelineSummarySurfacesCameraSourceSnapshot() throws {
        let configuration = CameraSourceConfiguration(
            captureMode: .videoWithoutAudio,
            preferredPosition: .front,
            mirroringMode: .on
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let pipeline = try RecordingPipeline(configuration: configuration, outputURL: outputURL)

        XCTAssertEqual(pipeline.snapshot.sourceTypeName, pipeline.summary.sourceTypeName)
        XCTAssertEqual(pipeline.snapshot.processorCount, pipeline.summary.processorCount)
        XCTAssertEqual(pipeline.snapshot.pipelineState, pipeline.summary.pipelineState)
        XCTAssertEqual(pipeline.snapshot.recorderState, pipeline.summary.recorderState)
        XCTAssertEqual(pipeline.snapshot.clipCount, pipeline.summary.clipCount)
        XCTAssertEqual(pipeline.snapshot.totalDuration, pipeline.summary.totalDuration)
        XCTAssertEqual(pipeline.snapshot.currentClipDuration, pipeline.summary.currentClipDuration)
        XCTAssertEqual(pipeline.snapshot.hasRecordedClip, pipeline.summary.hasRecordedClip)
        XCTAssertEqual(pipeline.snapshot.currentClipHasStarted, pipeline.summary.currentClipHasStarted)
        XCTAssertEqual(pipeline.snapshot.currentClipHasVideo, pipeline.summary.currentClipHasVideo)
        XCTAssertEqual(pipeline.snapshot.currentClipHasAudio, pipeline.summary.currentClipHasAudio)
        XCTAssertEqual(pipeline.snapshot.recordedVideoSegmentCount, pipeline.summary.recordedVideoSegmentCount)
        XCTAssertEqual(pipeline.snapshot.recordedAudioSegmentCount, pipeline.summary.recordedAudioSegmentCount)
        XCTAssertEqual(pipeline.snapshot.lastErrorDescription, pipeline.summary.lastErrorDescription)
        XCTAssertEqual(pipeline.summary.cameraSourceState, .idle)
        XCTAssertEqual(pipeline.summary.cameraSourcePosition, .front)
        XCTAssertEqual(pipeline.summary.cameraSourceAuthorizationStatus, pipeline.cameraSource?.authorizationStatus)
        XCTAssertEqual(pipeline.summary.cameraSourceIsPaused, false)
        XCTAssertEqual(pipeline.summary.cameraSourceCaptureMode, .videoWithoutAudio)
        XCTAssertNil(pipeline.summary.cameraSourceLastFrameIndex)
        XCTAssertNil(pipeline.summary.cameraSourceLastPresentationTime)
        XCTAssertNil(pipeline.summary.cameraSourceLastMediaType)
        XCTAssertEqual(pipeline.snapshot.cameraSourceSnapshot?.state, .idle)
        XCTAssertEqual(pipeline.snapshot.cameraSourceSnapshot?.position, .front)
        XCTAssertEqual(pipeline.snapshot.cameraSourceSnapshot?.authorizationStatus, pipeline.cameraSource?.authorizationStatus)
        XCTAssertEqual(pipeline.snapshot.cameraSourceSnapshot?.isPaused, false)
        XCTAssertEqual(pipeline.snapshot.cameraSourceSnapshot?.captureMode, .videoWithoutAudio)
    }
#endif

    func testRecordingPipelineSummaryIncludesFailureDescriptionFromUnderlyingPipeline() throws {
        let source = FailingSource(error: NSError(domain: "RecordingPipelineTests", code: 23))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let pipeline = try RecordingPipeline(source: source, outputURL: outputURL)
        let expectation = expectation(description: "recording pipeline failure")

        pipeline.pipeline.errorHandler = { error in
            XCTAssertEqual((error as NSError).domain, "RecordingPipelineTests")
            expectation.fulfill()
        }

        pipeline.start()

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.lastErrorDescription, "RecordingPipelineTests#23")
        XCTAssertEqual(pipeline.summary.lastErrorDescription, "RecordingPipelineTests#23")
        XCTAssertTrue(pipeline.summary.summaryText.contains("error RecordingPipelineTests#23"))
    }

    func testTimelinePipelineCompilesTimelineAndSummarizesBoardState() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip]
        )

        let compiled = pipeline.compile()

        XCTAssertEqual(pipeline.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(pipeline.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(pipeline.layers.count, 1)
        XCTAssertEqual(pipeline.transitions.count, 0)
        XCTAssertEqual(pipeline.summary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(pipeline.summary.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(pipeline.summary.layerCount, 1)
        XCTAssertEqual(pipeline.summary.transitionCount, 0)
        XCTAssertEqual(pipeline.summary.compiledSummary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(pipeline.summary.compiledSummary.videoLayerCount, 1)
        XCTAssertEqual(pipeline.summary.compiledSummary.processorCount, 0)
        XCTAssertEqual(compiled.summary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(compiled.summary.videoLayerCount, 1)
        XCTAssertEqual(pipeline.summary.compiledSummary.summaryText, compiled.summary.summaryText)
        XCTAssertTrue(pipeline.summaryText.contains("layers 1"))
        XCTAssertTrue(pipeline.summaryText.contains("transitions 0"))
        XCTAssertTrue(pipeline.summaryText.contains("processors 0"))
    }

    func testTimelinePipelineForwardsCompiledAssetImageAndProcessorHelpers() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let imageLayer = ImageLayer(
            source: StillImageSource(image: try makeImage(width: 20, height: 12)),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            layerLevel: 1
        )
        let effectLayer = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            source: EffectSource(processor: PassthroughFrameProcessor(), intensity: 0.6),
            layerLevel: 2
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip, imageLayer, effectLayer]
        )

        let compiled = pipeline.compile()
        let assetSources = pipeline.makeAssetSources()
        let imageSource = pipeline.makeImageSource()
        let processorChain = pipeline.makeProcessorChain()

        XCTAssertEqual(assetSources.count, compiled.makeAssetSources().count)
        XCTAssertNotNil(imageSource)
        XCTAssertEqual(processorChain.summary.summaryText, compiled.makeProcessorChain().summary.summaryText)
        XCTAssertTrue(pipeline.summaryText.contains("layers 3"))
        XCTAssertTrue(pipeline.summaryText.contains("processors 1"))
    }

    func testTimelinePipelineBuildsReaderWriterExportJobFromCompiledComposition() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip]
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let exportJob = pipeline.makeExportJob(outputURL: outputURL)

        XCTAssertEqual(exportJob.summary.status, .idle)
        XCTAssertEqual(exportJob.summary.processorCount, 0)
        XCTAssertGreaterThanOrEqual(exportJob.summary.videoTrackCount, 1)
        XCTAssertTrue(exportJob.summary.summaryText.contains("state idle"))
        XCTAssertTrue(exportJob.summary.summaryText.contains("tracks"))
    }

    func testTimelinePipelineBuildsTimelineExportTaskFromCompiledComposition() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip]
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let task = pipeline.makeExportTask(outputURL: outputURL)

        XCTAssertEqual(task.status, .idle)
        XCTAssertEqual(task.summary.layerCount, 1)
        XCTAssertEqual(task.summary.transitionCount, 0)
        XCTAssertEqual(task.summary.processorCount, 0)
        XCTAssertEqual(task.summary.compiledSummary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(task.summary.compiledSummary.videoLayerCount, 1)
        XCTAssertEqual(task.summary.compiledSummary.processorCount, 0)
        XCTAssertEqual(task.summary.compiledSummary.summaryText, pipeline.compile().summary.summaryText)
        XCTAssertTrue(task.summaryText.contains("export idle"))
        XCTAssertEqual(task.compiledComposition.summary.renderSize, CGSize(width: 1280, height: 720))
    }

    func testTimelineExportTaskForwardsProgressAndCompletion() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip]
        )
        let compiled = pipeline.compile()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let fakeSession = FakeReaderWriterExportSession()
        let job = ReaderWriterExportJob(
            asset: compiled.composition,
            outputURL: outputURL,
            fileType: .mp4,
            timeRange: CMTimeRange(start: .zero, duration: compiled.composition.duration),
            videoComposition: compiled.videoComposition,
            audioMix: compiled.audioMix,
            videoProcessors: [],
            shouldOptimizeForNetworkUse: true,
            metadata: [],
            sessionFactory: { _, _, _ in fakeSession }
        )
        let task = TimelineExportTask(compiledComposition: compiled, readerWriterJob: job)
        let progressExpectation = expectation(description: "forward progress")
        let completionExpectation = expectation(description: "export complete")
        var receivedProgress: [Float] = []
        var receivedInfo: ReaderWriterExportJob.ProgressInfo?

        task.start(
            complete: { result in
                switch result {
                case .success(let url):
                    XCTAssertEqual(url, outputURL)
                case .failure(let error):
                    XCTFail("Unexpected export failure: \(error)")
                }
                completionExpectation.fulfill()
            },
            progress: { progress in
                receivedProgress.append(progress)
                if receivedProgress.count == 1 {
                    progressExpectation.fulfill()
                }
            },
            progressInfo: { info in
                receivedInfo = info
            }
        )

        fakeSession.emitStatus(.exporting)
        fakeSession.emitProgress(
            ReaderWriterExportSessionProgress(
                videoProgress: 0.5,
                audioProgress: 0.25,
                hasVideo: true,
                hasAudio: true,
                finishWritingProgress: 0.4
            )
        )
        fakeSession.finish(with: nil)

        wait(for: [progressExpectation, completionExpectation], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.progressFraction ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(receivedProgress.first ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(receivedProgress.last ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertNotNil(receivedInfo)
        XCTAssertEqual(task.summary.compiledSummary.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(task.summary.compiledSummary.videoLayerCount, 1)
        XCTAssertEqual(task.summary.compiledSummary.processorCount, 0)
        XCTAssertEqual(task.summary.compiledSummary.summaryText, compiled.summary.summaryText)
        XCTAssertTrue(task.summaryText.contains("export completed"))
    }

    func testTimelineExportJobDefaultsToCompiledEffectProcessors() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let effectLayer = EffectLayer(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            source: EffectSource(processor: PassthroughFrameProcessor(), intensity: 0.8),
            layerLevel: 1
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip, effectLayer]
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let exportJob = pipeline.makeExportJob(outputURL: outputURL)

        XCTAssertEqual(exportJob.summary.processorCount, 1)
        XCTAssertTrue(exportJob.summary.summaryText.contains("processors 1"))
    }

    #if canImport(UIKit) || os(macOS)
    func testTimelinePipelineCreatesPlayerItemAndPreviewPipeline() throws {
        let asset = AVAsset(url: try makeSampleAssetURL())
        let clip = ClipLayer(
            asset: asset,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30)),
            sourceTimeRange: CMTimeRange(start: .zero, duration: CMTime(value: 30, timescale: 30))
        )
        let pipeline = TimelinePipeline(
            renderSize: CGSize(width: 1280, height: 720),
            frameDuration: CMTime(value: 1, timescale: 30),
            layers: [clip]
        )

        let playerItem = pipeline.makePlayerItem()
        let previewPipeline = pipeline.makePreviewPipeline(handler: { _, _ in })

        XCTAssertEqual(playerItem.videoComposition?.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertNotNil(playerItem.audioMix)
        XCTAssertTrue(previewPipeline.source is PlayerFrameSource)
        XCTAssertEqual(previewPipeline.summary.sourceTypeName, "PlayerFrameSource")
    }
    #endif

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

    func testCameraSessionLifecycleTracksPauseResumeAuthorizationAndPositionSwitch() {
        var lifecycle = CameraSessionLifecycle(position: .back, authorizationStatus: .notDetermined)

        XCTAssertEqual(lifecycle.handle(.startRequested), .authorizationChanged(.notDetermined))
        XCTAssertEqual(lifecycle.state, .unauthorized)

        XCTAssertEqual(lifecycle.handle(.authorizationChanged(.authorized)), .authorizationChanged(.authorized))
        XCTAssertEqual(lifecycle.state, .idle)

        XCTAssertEqual(lifecycle.handle(.startRequested), .willStart)
        XCTAssertEqual(lifecycle.handle(.didStartRunning), .didStart)
        XCTAssertEqual(lifecycle.handle(.pauseRequested), .didPause)
        XCTAssertEqual(lifecycle.state, .paused)
        XCTAssertEqual(lifecycle.handle(.resumeRequested), .didResume)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.handle(.positionSwitchRequested(.front)), .willSwitchPosition(.front))
        XCTAssertEqual(lifecycle.state, .reconfiguring)
        XCTAssertEqual(lifecycle.handle(.positionChanged(.front)), .positionChanged(.front))
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.position, .front)
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
        XCTAssertEqual(lifecycle.state, .recovering)
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

    func testCameraSourceConfigurationRequestedMediaTypesMatchCaptureMode() {
        XCTAssertEqual(CameraSourceConfiguration(captureMode: .video).requestedMediaTypes, [.video, .audio])
        XCTAssertEqual(CameraSourceConfiguration(captureMode: .videoWithoutAudio).requestedMediaTypes, [.video])
        XCTAssertEqual(CameraSourceConfiguration(captureMode: .photo).requestedMediaTypes, [.video])
    }

    func testCameraSourceConfigurationMirroringAndAuthorizationHelpers() {
        let configuration = CameraSourceConfiguration(
            captureMode: .video,
            preferredPosition: .front,
            mirroringMode: .automatic
        )

        XCTAssertTrue(configuration.requiresAuthorization(for: .video))
        XCTAssertTrue(configuration.requiresAuthorization(for: .audio))
        XCTAssertFalse(configuration.requiresAuthorization(for: .metadata))
        XCTAssertTrue(configuration.effectiveMirroringValue(for: .front))
        XCTAssertFalse(configuration.effectiveMirroringValue(for: .back))
    }

    func testCameraAspectRatioResolvesDimensionsFromSourceSize() {
        let sourceSize = CGSize(width: 1080, height: 1920)

        XCTAssertEqual(CameraAspectRatio.active.resolvedDimensions(from: sourceSize), sourceSize)
        XCTAssertEqual(CameraAspectRatio.square.resolvedDimensions(from: sourceSize), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(CameraAspectRatio.standard.resolvedDimensions(from: sourceSize), CGSize(width: 1080, height: 1440))
        XCTAssertEqual(CameraAspectRatio.widescreenLandscape.resolvedDimensions(from: sourceSize), CGSize(width: 1080, height: 608))
        XCTAssertEqual(CameraAspectRatio.custom(width: 4, height: 5).resolvedDimensions(from: sourceSize), CGSize(width: 1080, height: 1350))
    }

    #if canImport(UIKit) && !os(watchOS)
    func testCameraSourceSummaryReflectsSessionStateAndCaptureConfiguration() throws {
        let configuration = CameraSourceConfiguration(
            captureMode: .videoWithoutAudio,
            preferredPosition: .front,
            mirroringMode: .on
        )
        let source = try CameraSource(configuration: configuration)

        XCTAssertEqual(source.snapshot.state, source.summary.state)
        XCTAssertEqual(source.snapshot.position, source.summary.position)
        XCTAssertEqual(source.snapshot.authorizationStatus, source.summary.authorizationStatus)
        XCTAssertEqual(source.snapshot.isPaused, source.summary.isPaused)
        XCTAssertEqual(source.snapshot.captureMode, source.summary.captureMode)
        XCTAssertEqual(source.snapshot.deviceOrientation, source.summary.deviceOrientation)
        XCTAssertEqual(source.snapshot.isMirrored, source.summary.isMirrored)
        XCTAssertEqual(source.summary.state, .idle)
        XCTAssertEqual(source.summary.position, .front)
        XCTAssertEqual(source.summary.authorizationStatus, source.authorizationStatus)
        XCTAssertEqual(source.summary.isPaused, false)
        XCTAssertEqual(source.summary.captureMode, .videoWithoutAudio)
        XCTAssertEqual(
            source.summary.summaryText,
            "state idle · position front · auth \(source.authorizationStatus.description) · paused no · mode videoWithoutAudio"
        )

        source._setStateForTesting(.running)
        source.pause()
        XCTAssertEqual(source.summary.state, .paused)
        XCTAssertTrue(source.summary.summaryText.contains("state paused"))
    }

    func testCameraSourceOwnsNativePreviewLayerAndAppliesConfiguredSessionPreset() throws {
        let configuration = CameraSourceConfiguration(
            captureMode: .videoWithoutAudio,
            preferredPosition: .back,
            previewGravity: .resizeAspect,
            video: CameraVideoConfiguration(sessionPreset: .medium)
        )
        let source = try CameraSource(configuration: configuration)

        XCTAssertTrue(source.previewLayer.session === source.session)
        XCTAssertEqual(source.previewLayer.videoGravity, .resizeAspect)
        XCTAssertEqual(source.session.sessionPreset, .medium)
    }

    func testCameraSourcePausesAndResumesFrameEmissionWithSessionMetadata() throws {
        let configuration = CameraSourceConfiguration(captureMode: .videoWithoutAudio)
        let source = try CameraSource(configuration: configuration)
        let firstBuffer = try makeSampleBuffer(width: 16, height: 10, presentationTime: CMTime(value: 1, timescale: 30))
        let secondBuffer = try makeSampleBuffer(width: 24, height: 14, presentationTime: CMTime(value: 2, timescale: 30))
        var receivedFrames: [MediaFrame] = []

        source._setStateForTesting(.running)
        source.frameHandler = { frame in
            receivedFrames.append(frame)
        }

        source._emitForTesting(sampleBuffer: firstBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 1)
        XCTAssertEqual(receivedFrames[0].metadata.frameIndex, 1)
        XCTAssertEqual(receivedFrames[0].metadata.userInfo[CameraSource.MetadataKey.sessionState] as? String, "running")
        XCTAssertEqual(receivedFrames[0].metadata.userInfo[CameraSource.MetadataKey.mediaType] as? String, AVMediaType.video.rawValue)
        XCTAssertEqual(source.summary.lastFrameIndex, 1)
        XCTAssertEqual(source.summary.lastPresentationTime, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(source.summary.lastMediaType, AVMediaType.video.rawValue)
        XCTAssertEqual(source.snapshot.lastFrameIndex, source.summary.lastFrameIndex)
        XCTAssertEqual(source.snapshot.lastPresentationTime, source.summary.lastPresentationTime)
        XCTAssertEqual(source.snapshot.lastMediaType, source.summary.lastMediaType)
        XCTAssertTrue(source.summary.summaryText.contains("frame 1"))
        XCTAssertTrue(source.summary.summaryText.contains("presentation 0.03s"))
        XCTAssertTrue(source.summary.summaryText.contains("mediaType video"))

        source.pause()
        XCTAssertEqual(source.state, .paused)
        source._emitForTesting(sampleBuffer: secondBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 1)

        source.resume()
        XCTAssertEqual(source.state, .running)
        source._emitForTesting(sampleBuffer: secondBuffer, mediaType: .video)

        XCTAssertEqual(receivedFrames.count, 2)
        XCTAssertEqual(receivedFrames[1].metadata.frameIndex, 2)
        XCTAssertEqual(receivedFrames[1].metadata.userInfo[CameraSource.MetadataKey.sessionState] as? String, "running")
        XCTAssertEqual(receivedFrames[1].metadata.userInfo[CameraSource.MetadataKey.mediaType] as? String, AVMediaType.video.rawValue)
        XCTAssertEqual(source.summary.lastFrameIndex, 2)
        XCTAssertEqual(source.summary.lastPresentationTime, CMTime(value: 2, timescale: 30))
        XCTAssertEqual(source.summary.lastMediaType, AVMediaType.video.rawValue)
        XCTAssertEqual(source.snapshot.lastFrameIndex, source.summary.lastFrameIndex)
        XCTAssertEqual(source.snapshot.lastPresentationTime, source.summary.lastPresentationTime)
        XCTAssertEqual(source.snapshot.lastMediaType, source.summary.lastMediaType)
    }

    func testCameraSourceIgnoresLateFramesAfterStopAndCancel() throws {
        let configuration = CameraSourceConfiguration(captureMode: .videoWithoutAudio)
        let source = try CameraSource(configuration: configuration)
        let firstBuffer = try makeSampleBuffer(width: 20, height: 12, presentationTime: CMTime(value: 1, timescale: 30))
        let secondBuffer = try makeSampleBuffer(width: 28, height: 18, presentationTime: CMTime(value: 2, timescale: 30))
        var receivedFrames: [MediaFrame] = []

        source._setStateForTesting(.running)
        source.frameHandler = { frame in
            receivedFrames.append(frame)
        }

        source._emitForTesting(sampleBuffer: firstBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 1)
        XCTAssertEqual(receivedFrames[0].metadata.frameIndex, 1)

        source.stop()
        source._emitForTesting(sampleBuffer: secondBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 1)

        source.start()
        source._setStateForTesting(.running)
        source._emitForTesting(sampleBuffer: secondBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 2)
        XCTAssertEqual(receivedFrames[1].metadata.frameIndex, 1)

        source.cancel()
        source._emitForTesting(sampleBuffer: secondBuffer, mediaType: .video)
        XCTAssertEqual(receivedFrames.count, 2)
    }

    func testCameraSourceInterruptionCallbacksAndSnapshotStayInSync() throws {
        let source = try CameraSource(configuration: .init(captureMode: .videoWithoutAudio))
        var events: [CameraSessionEvent] = []
        var observerEvents: [CameraSessionEvent] = []

        source.sessionEventHandler = { event in
            events.append(event)
        }
        _ = source.addSessionEventObserver { observerEvents.append($0) }

        source._handleLifecycleActionForTesting(.didStartRunning)
        source._handleLifecycleActionForTesting(.wasInterrupted)
        source._handleLifecycleActionForTesting(.interruptionEnded)

        XCTAssertEqual(events, [.didStart, .wasInterrupted, .interruptionEnded])
        XCTAssertEqual(observerEvents, [.didStart, .wasInterrupted, .interruptionEnded])
        XCTAssertEqual(source.snapshot.state, .running)
        XCTAssertEqual(source.summary.state, .running)
    }

    func testCameraSourceRecordingAwareInterruptionPublishesDedicatedEventAndResumes() throws {
        let source = try CameraSource(configuration: .init(captureMode: .videoWithoutAudio))
        var events: [CameraSessionEvent] = []
        source.sessionEventHandler = { events.append($0) }

        source._handleLifecycleActionForTesting(.didStartRunning)
        source._handleSessionInterruptionForTesting(recordingActive: true)
        source._handleSessionInterruptionEndedForTesting()

        XCTAssertEqual(events, [.didStart, .wasInterruptedWhileRecording, .interruptionEnded])
        XCTAssertEqual(source.snapshot.state, .running)
        XCTAssertFalse(source.snapshot.isPaused)
    }

    func testCameraSourcePositionAndAuthorizationTestingHooksUpdateSnapshotDetails() throws {
        let source = try CameraSource(
            configuration: .init(
                captureMode: .videoWithoutAudio,
                preferredPosition: .back,
                mirroringMode: .automatic
            )
        )

        source._handleLifecycleActionForTesting(.positionChanged(.front))
        source._handleLifecycleActionForTesting(.authorizationChanged(.denied))

        XCTAssertEqual(source.snapshot.position, .front)
        XCTAssertEqual(source.summary.position, .front)
        XCTAssertEqual(source.snapshot.authorizationStatus, .denied)
        XCTAssertEqual(source.summary.authorizationStatus, .denied)
        XCTAssertTrue(source.snapshot.isMirrored)
        XCTAssertEqual(source.sourceSnapshot.details["position"], "front")
        XCTAssertEqual(source.sourceSnapshot.details["auth"], "denied")
    }
    #endif

    func testRecordingSessionAccumulatesMultipleSegmentsAndTracksAudioVideoFlags() {
        let session = RecordingSession()

        session.markVideoFrame(at: .zero)
        session.pause(at: CMTime(value: 30, timescale: 30))
        session.finalizeCurrentClipIfNeeded(preferredEndTime: CMTime(value: 30, timescale: 30))
        session.resume(at: CMTime(value: 90, timescale: 30))
        session.markAudioFrame(at: CMTime(value: 30, timescale: 30))
        session.markVideoFrame(at: CMTime(value: 60, timescale: 30))
        session.finalizeCurrentClipIfNeeded(preferredEndTime: CMTime(value: 60, timescale: 30))

        let snapshot = session.snapshot()

        XCTAssertEqual(snapshot.clipCount, 2)
        XCTAssertEqual(snapshot.recordedVideoSegmentCount, 2)
        XCTAssertEqual(snapshot.recordedAudioSegmentCount, 1)
        XCTAssertEqual(snapshot.totalDuration, CMTime(value: 60, timescale: 30))
        XCTAssertEqual(session.clips.first?.containsAudio, false)
        XCTAssertEqual(session.clips.last?.containsAudio, true)
        XCTAssertEqual(session.clips.last?.containsVideo, true)
    }

    func testRecorderSinkMultiSegmentSummaryTracksFinishedSegmentCounts() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let sink = try RecorderSink(outputURL: outputURL)
        let pixelBuffer = try makePixelBuffer(width: 32, height: 32)
        let first = MediaFrame(pixelBuffer: pixelBuffer, metadata: FrameMetadata(presentationTime: .zero))
        let second = MediaFrame(
            pixelBuffer: pixelBuffer,
            metadata: FrameMetadata(presentationTime: CMTime(value: 90, timescale: 30))
        )
        let appendExpectation = expectation(description: "append multi segment frames")
        appendExpectation.expectedFulfillmentCount = 2
        let finishExpectation = expectation(description: "finish multi segment recording")
        var recordedClip: RecordedClip?

        sink.consume(first) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected recorder failure: \(error)")
            }
            appendExpectation.fulfill()
        }

        sink.pauseRecording(at: CMTime(value: 30, timescale: 30))
        sink.resumeRecording()

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

        XCTAssertEqual(sink.summary.clipCount, 2)
        XCTAssertEqual(sink.summary.recordedVideoSegmentCount, 2)
        XCTAssertEqual(sink.summary.recordedAudioSegmentCount, 0)
        XCTAssertEqual(recordedClip?.segments.count, 2)
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

private final class SnapshotSource: MediaSource, MediaSourceSnapshotProviding {
    weak var delegate: MediaSourceDelegate?
    private let frames: [MediaFrame]
    let sourceSnapshot: MediaSourceSnapshot

    init(frames: [MediaFrame], snapshot: MediaSourceSnapshot) {
        self.frames = frames
        self.sourceSnapshot = snapshot
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

private enum SequencedSourceEvent {
    case output(MediaFrame)
    case fail(Error)
    case finish
}

private final class SequencedSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private let runs: [[SequencedSourceEvent]]
    private var startCount = 0

    init(runs: [[SequencedSourceEvent]]) {
        self.runs = runs
    }

    func start() {
        guard runs.isEmpty == false else {
            delegate?.mediaSourceDidFinish(self)
            return
        }
        let index = min(startCount, runs.count - 1)
        startCount += 1
        runs[index].forEach { event in
            switch event {
            case .output(let frame):
                delegate?.mediaSource(self, didOutput: frame)
            case .fail(let error):
                delegate?.mediaSource(self, didFail: error)
            case .finish:
                delegate?.mediaSourceDidFinish(self)
            }
        }
    }

    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}

private final class ManualSource: MediaSource {
    weak var delegate: MediaSourceDelegate?

    func start() {}
    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}

    func emit(_ frame: MediaFrame) {
        delegate?.mediaSource(self, didOutput: frame)
    }

    func finish() {
        delegate?.mediaSourceDidFinish(self)
    }

    func fail(_ error: Error) {
        delegate?.mediaSource(self, didFail: error)
    }
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

private struct ReaderWriterExportSessionProgress {
    let videoProgress: Double
    let audioProgress: Double
    let hasVideo: Bool
    let hasAudio: Bool
    let finishWritingProgress: Double
}

private final class FakeReaderWriterExportSession: ReaderWriterExportSession {
    private var progressHandler: ((VideoAssetExportSession.ExportProgress) -> Void)?
    private var statusHandler: ((VideoAssetExportSession.Status) -> Void)?
    private var completionHandler: ((Error?) -> Void)?
    private(set) var cancelCallCount = 0

    func export(
        progress: ((VideoAssetExportSession.ExportProgress) -> Void)?,
        status: ((VideoAssetExportSession.Status) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) {
        progressHandler = progress
        statusHandler = status
        completionHandler = completion
    }

    func pause() {}
    func resume() {}
    func cancel() {
        cancelCallCount += 1
    }

    func emitStatus(_ status: VideoAssetExportSession.Status) {
        statusHandler?(status)
    }

    func emitProgress(_ snapshot: ReaderWriterExportSessionProgress) {
        let progress = VideoAssetExportSession.ExportProgress(
            tracksAudioEncoding: snapshot.hasAudio,
            tracksVideoEncoding: snapshot.hasVideo
        )
        progress.updateVideoEncodingProgress(fractionCompleted: snapshot.videoProgress)
        progress.updateAudioEncodingProgress(fractionCompleted: snapshot.audioProgress)
        progress.updateFinishWritingProgress(fractionCompleted: snapshot.finishWritingProgress)
        progressHandler?(progress)
    }

    func finish(with error: Error?) {
        completionHandler?(error)
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

private final class CountingStopSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private(set) var stopCount = 0

    func start() {}
    func pause() {}
    func resume() {}

    func stop() {
        stopCount += 1
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

private final class FailingFinishSink: MediaSink {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(error))
    }
}

private final class FailingSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func start() {
        delegate?.mediaSource(self, didFail: error)
    }

    func pause() {}
    func resume() {}
    func stop() {}
    func cancel() {}
}

private final class ObservableProgressSession: NSObject {
    @objc dynamic var progress: Float = 0
}

private final class DelayedEmittingSource: MediaSource {
    weak var delegate: MediaSourceDelegate?
    private let frames: [MediaFrame]
    private let emissionDelay: TimeInterval
    private let queue = DispatchQueue(label: "com.condy.kakapos.tests.delayed-emitting-source")
    private let lock = NSLock()
    private var cancelled = false
    private(set) var cancelCount = 0
    private(set) var emissionCount = 0

    init(frames: [MediaFrame], emissionDelay: TimeInterval) {
        self.frames = frames
        self.emissionDelay = emissionDelay
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            for (index, frame) in self.frames.enumerated() {
                if index > 0 {
                    Thread.sleep(forTimeInterval: self.emissionDelay)
                }
                if self.isCancelled {
                    return
                }
                self.lock.lock()
                self.emissionCount += 1
                self.lock.unlock()
                self.delegate?.mediaSource(self, didOutput: frame)
            }
            if self.isCancelled {
                return
            }
            self.delegate?.mediaSourceDidFinish(self)
        }
    }

    func pause() {}
    func resume() {}
    func stop() {}

    func cancel() {
        lock.lock()
        cancelCount += 1
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class FailingConsumeSink: MediaSink {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(error))
    }
}

#if canImport(UIKit) && !os(watchOS)
private func makeSampleBuffer(
    width: Int,
    height: Int,
    presentationTime: CMTime
) throws -> CMSampleBuffer {
    let pixelBuffer = try makePixelBuffer(width: width, height: height)
    var sampleBuffer: CMSampleBuffer?
    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    XCTAssertEqual(formatStatus, noErr)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription!,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    XCTAssertEqual(createStatus, noErr)
    return try XCTUnwrap(sampleBuffer)
}
#endif

private final class TestConsumerNode: MediaFrameConsumerNode {
    var onFrame: ((MediaFrame) -> Void)?

    func consume(_ frame: MediaFrame, from source: MediaFrameSourceNode, completion: @escaping (Result<Void, Error>) -> Void) {
        onFrame?(frame)
        completion(.success(()))
    }
}

#if canImport(UIKit) || os(macOS)
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

private final class SyntheticReaderWriterExportSession: ReaderWriterExportSession {
    private let processors: [FrameProcessor]
    private let frame: MediaFrame
    private let outputURL: URL

    init(processors: [FrameProcessor], frame: MediaFrame, outputURL: URL) {
        self.processors = processors
        self.frame = frame
        self.outputURL = outputURL
    }

    func export(
        progress: ((VideoAssetExportSession.ExportProgress) -> Void)?,
        status: ((VideoAssetExportSession.Status) -> Void)?,
        completion: @escaping (Error?) -> Void
    ) {
        status?(.exporting)
        let progressInfo = VideoAssetExportSession.ExportProgress(
            tracksAudioEncoding: false,
            tracksVideoEncoding: true
        )
        progressInfo.updateVideoEncodingProgress(fractionCompleted: 0.5)
        progress?(progressInfo)
        process(frame: frame, at: 0) { result in
            switch result {
            case .success:
                progressInfo.updateFinishWritingProgress(fractionCompleted: 1.0)
                progress?(progressInfo)
                FileManager.default.createFile(atPath: self.outputURL.path, contents: Data([0]), attributes: nil)
                status?(.completed)
                completion(nil)
            case .failure(let error):
                status?(.failed)
                completion(error)
            }
        }
    }

    func pause() {}
    func resume() {}
    func cancel() {}

    private func process(
        frame: MediaFrame,
        at index: Int,
        completion: @escaping (Result<MediaFrame, Error>) -> Void
    ) {
        guard index < processors.count else {
            completion(.success(frame))
            return
        }
        processors[index].process(frame) { [weak self] result in
            guard let self else {
                completion(.failure(NSError(domain: "KakaposTests", code: -1)))
                return
            }
            switch result {
            case .success(let nextFrame):
                self.process(frame: nextFrame, at: index + 1, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

private func makeSampleExporter() throws -> VideoX {
    let sampleURL = try makeSampleAssetURL()
    XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    return VideoX(provider: .init(with: sampleURL, to: outputURL))
}

private func makeSampleAssetURL() throws -> URL {
    let baseURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("KakaposExamples")
    let preferredURLs = [
        baseURL.appendingPathComponent("IMG_3156.MOV"),
        baseURL.appendingPathComponent("IMG_1388.mp4")
    ]
    for sampleURL in preferredURLs where FileManager.default.fileExists(atPath: sampleURL.path) {
        return sampleURL
    }
    XCTFail("Expected a sample asset under KakaposExamples.")
    return baseURL.appendingPathComponent("IMG_3156.MOV")
}
