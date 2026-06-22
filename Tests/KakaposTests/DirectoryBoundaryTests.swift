import XCTest

final class DirectoryBoundaryTests: XCTestCase {

    func testSourcesUseEngineOwnedTopLevelDirectories() throws {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let topLevelDirectories = try entries.compactMap { url -> String? in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? url.lastPathComponent : nil
        }.sorted()

        XCTAssertEqual(topLevelDirectories, ["CameraEngine", "Core", "MediaCore", "TimelineEngine", "VideoEngine"])
    }

    func testLegacyTopLevelDirectoriesDoNotReturn() {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources", isDirectory: true)
        let legacyDirectories = ["Instructions", "Pipeline", "Processing", "RealtimeCore", "Setup", "Timeline"]

        for directory in legacyDirectories {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(directory, isDirectory: true).path),
                "\(directory) should be folded into the engine-owned directory layout."
            )
        }
    }

    func testEngineBoundaryOwnsKnownSourceFiles() {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources", isDirectory: true)
        let expectedFiles = [
            "Core/KakaposSurface.swift",
            "Core/Setup/Kakapos.swift",
            "MediaCore/Frame/MediaFrame.swift",
            "MediaCore/Frame/SampleBufferUtilities.swift",
            "MediaCore/Processing/FrameProcessor.swift",
            "MediaCore/Processing/HarbethFrameProcessor.swift",
            "MediaCore/Pipeline/MediaSource.swift",
            "MediaCore/Pipeline/MediaSink.swift",
            "MediaCore/Pipeline/MediaPipeline.swift",
            "VideoEngine/Sources/PlayerFrameSource.swift",
            "VideoEngine/Preview/PreviewPipeline.swift",
            "VideoEngine/Export/Core/VideoX.swift",
            "VideoEngine/Export/Core/ReaderWriterExportJob.swift",
            "VideoEngine/Export/Instructions/Instruction.swift",
            "VideoEngine/Export/Instructions/FilterInstruction.swift",
            "VideoEngine/Export/Instructions/WatermarkInstruction.swift",
            "CameraEngine/CameraEngine.swift",
            "CameraEngine/Capture/CameraSource.swift",
            "CameraEngine/Capture/MultiCameraSource.swift",
            "CameraEngine/Device/CameraDeviceController.swift",
            "CameraEngine/Device/CameraSourceConfiguration.swift",
            "CameraEngine/Preview/CameraPreviewSink.swift",
            "CameraEngine/Preview/CameraPreviewController.swift",
            "CameraEngine/Recording/RecorderSink.swift",
            "CameraEngine/Recording/RecordingPipeline.swift",
            "CameraEngine/Recording/CameraRecordingController.swift",
            "CameraEngine/Diagnostics/CameraDiagnostics.swift",
            "CameraEngine/Session/CameraAudioSessionController.swift",
            "TimelineEngine/TimelineComposition.swift",
            "TimelineEngine/TimelineCompiler.swift",
            "TimelineEngine/Transition.swift",
        ]

        for path in expectedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(path).path),
                "\(path) should remain in its engine-owned directory."
            )
        }
    }

    func testCameraEngineUsesOwnedSubdirectories() throws {
        let cameraRoot = repositoryRoot().appendingPathComponent("Sources/CameraEngine", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: cameraRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let topLevelDirectories = try entries.compactMap { url -> String? in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? url.lastPathComponent : nil
        }.sorted()

        XCTAssertEqual(
            topLevelDirectories,
            ["Capture", "Device", "Diagnostics", "Preview", "Recording", "Session"]
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
