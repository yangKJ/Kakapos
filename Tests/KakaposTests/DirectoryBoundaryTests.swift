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
            "VideoEngine/Setup/Kakapos.swift",
            "MediaCore/Frame/MediaFrame.swift",
            "MediaCore/Frame/SampleBufferUtilities.swift",
            "MediaCore/Processing/FrameProcessor.swift",
            "MediaCore/Pipeline/MediaSource.swift",
            "MediaCore/Pipeline/MediaSink.swift",
            "MediaCore/Pipeline/MediaPipeline.swift",
            "VideoEngine/Sources/PlayerFrameSource.swift",
            "VideoEngine/Preview/PreviewPipeline.swift",
            "VideoEngine/Preview/VideoPreviewMode.swift",
            "VideoEngine/Preview/VideoPreviewProcessingLane.swift",
            "VideoEngine/Preview/VideoPreviewSession.swift",
            "VideoEngine/Preview/VideoPreviewSurface.swift",
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
            "CameraEngine/Diagnostics/CameraEventDispatcher.swift",
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

    func testCoreSourcesDoNotDependOnHarbeth() throws {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let forbiddenFragments = [
            "import Harbeth",
            "C7FilterProtocol",
            "HarbethIO",
            "C7Blend",
            "TextureLoader"
        ]

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for fragment in forbiddenFragments {
                XCTAssertFalse(
                    source.contains(fragment),
                    "\(url.path) must keep Harbeth integration outside Kakapos Core."
                )
            }
        }
    }

    func testDistributionManifestsAgreeOnIOS13Minimum() throws {
        let root = repositoryRoot()
        let packageManifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let podspec = try String(
            contentsOf: root.appendingPathComponent("Kakapos.podspec"),
            encoding: .utf8
        )
        let swiftVersion = try String(
            contentsOf: root.appendingPathComponent(".swift-version"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(packageManifest.contains(".iOS(.v13)"))
        XCTAssertTrue(packageManifest.contains("swiftLanguageModes: [.v5]"))
        XCTAssertTrue(podspec.contains("s.ios.deployment_target = '13.0'"))
        XCTAssertTrue(podspec.contains("s.swift_version    = '5.0'"))
        XCTAssertTrue(podspec.contains("'SWIFT_VERSION' => '5.0'"))
        XCTAssertEqual(swiftVersion, "5.0")
        XCTAssertFalse(packageManifest.contains(".iOS(.v12)"))
        XCTAssertFalse(podspec.contains("s.ios.deployment_target = '12.0'"))
    }

    func testPackageExposesEngineProductsAndAThinUmbrella() throws {
        let packageManifest = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for product in ["KakaposMediaCore", "KakaposVideo", "KakaposTimeline", "KakaposCamera", "Kakapos"] {
            XCTAssertTrue(packageManifest.contains(".library(name: \"\(product)\""))
        }
        XCTAssertTrue(packageManifest.contains("name: \"KakaposVideo\",\n            dependencies: [\"KakaposMediaCore\"]"))
        XCTAssertTrue(packageManifest.contains("name: \"KakaposTimeline\",\n            dependencies: [\"KakaposMediaCore\", \"KakaposVideo\"]"))
        XCTAssertTrue(packageManifest.contains("name: \"KakaposCamera\",\n            dependencies: [\"KakaposMediaCore\", \"KakaposVideo\"]"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot().appendingPathComponent("Sources/Core/KakaposBoards.swift").path
            )
        )
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
