// 作者：Condy
#if os(macOS)
import AVFoundation
import XCTest
import KakaposMediaCore
import KakaposVideo
import KakaposTimeline

final class MediaResourceAcceptanceTests: XCTestCase {
    private func compiled(_ url: URL, invalid: Bool = false) -> CompiledTimelineComposition {
        let layer = ClipLayer(asset: AVURLAsset(url: url), timeRange: Round2Fixtures.range(0, 2), sourceTimeRange: Round2Fixtures.range(0, invalid ? 1 : 2))
        let text = TextLayer(attributedText: NSAttributedString(string: ""), frame: CGRect(x: 0, y: 0, width: 64, height: 64), timeRange: Round2Fixtures.range(0, 2))
        return TimelineComposition(renderSize: CGSize(width: 64, height: 64), layers: [layer, text]).compile()
    }
    func testExportTaskAndJobReleaseAfterEveryTerminalState() throws {
        let source = try Round2Fixtures.movie(self); defer { try? FileManager.default.removeItem(at: source) }
        for mode in ["success", "failure", "cancel"] {
            let output = Round2Fixtures.url(); defer { try? FileManager.default.removeItem(at: output) }
            weak var weakTask: TimelineExportTask?
            weak var weakJob: ReaderWriterExportJob?
            let done = expectation(description: mode)
            do {
                let processors: [FrameProcessor] = mode == "cancel" ? [ClosureFrameProcessor { _, _ in }] : []
                var task: TimelineExportTask? = TimelineExportTask(compiledComposition: compiled(source, invalid: mode == "failure"), outputURL: output, videoProcessors: processors)
                weakTask = task; weakJob = task?.readerWriterJob
                task?.start(complete: { result in
                    if mode == "success", case .failure(let error) = result { XCTFail("\(error)") }
                    if mode != "success", case .success = result { XCTFail("错误路径不应成功") }
                    done.fulfill()
                }, progress: { [retained = task!] _ in _ = retained.status })
                if mode == "cancel" { task?.cancel() }
                task = nil
            }
            wait(for: [done], timeout: 15)
            let deadline = Date().addingTimeInterval(2)
            while (weakTask != nil || weakJob != nil) && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
            XCTAssertNil(weakTask, mode); XCTAssertNil(weakJob, mode)
        }
    }
    @MainActor
    private func spin(_ seconds: Double = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.003)) }
        XCTAssertTrue(condition(), "播放器条件等待超时")
    }
    @MainActor
    private func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.003)) }
    }
    @MainActor
    func testSwitchStopAndDeinitDetachOnlyOwnedPlayerOutputs() throws {
        let url = try Round2Fixtures.movie(self); defer { try? FileManager.default.removeItem(at: url) }
        let items = (0..<4).map { _ in AVPlayerItem(url: url) }
        let external = items.map { item -> AVPlayerItemVideoOutput in let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil); item.add(output); return output }
        let player = AVPlayer(playerItem: items[0])
        var source: PlayerFrameSource? = PlayerFrameSource(player: player, suppressesPlayerRendering: true)
        source?.start(); spin { items[0].outputs.count == 2 }
        for index in 1..<items.count {
            player.replaceCurrentItem(with: items[index]); spin { items[index].outputs.count == 2 }
            for old in items[..<index] { XCTAssertEqual(old.outputs.count, 1) }
        }
        source?.stop()
        XCTAssertEqual(items.map { $0.outputs.count }, [1, 1, 1, 1])
        source?.start(); spin { items[3].outputs.count == 2 }
        source = nil
        XCTAssertEqual(items.map { $0.outputs.count }, [1, 1, 1, 1])
        for (item, output) in zip(items, external) { XCTAssertTrue(item.outputs.contains(output)) }
    }
    @MainActor
    func testReplacingWithNilAndReattachingDoesNotAccumulateOutputs() throws {
        let url = try Round2Fixtures.movie(self); defer { try? FileManager.default.removeItem(at: url) }
        let item = AVPlayerItem(url: url); let player = AVPlayer(playerItem: item)
        let source = PlayerFrameSource(player: player); source.start(); spin { item.outputs.count == 1 }
        for _ in 0..<3 {
            player.replaceCurrentItem(with: nil); XCTAssertTrue(item.outputs.isEmpty)
            player.replaceCurrentItem(with: item); spin { item.outputs.count == 1 }
        }
        source.cancel(); XCTAssertTrue(item.outputs.isEmpty)
    }
    @MainActor
    func testPlaybackCadenceMatrixAndExplicitRefresh() throws {
        for fps in [24, 30, 60] {
            let url = try Round2Fixtures.movie(self, framesPerSecond: fps); defer { try? FileManager.default.removeItem(at: url) }
            for requested in [30, 60] { for rate: Float in [0.5, 1, 2] {
                let item = AVPlayerItem(url: url); let player = AVPlayer(playerItem: item)
                let source = PlayerFrameSource(player: player, preferredFramesPerSecond: requested)
                var pts: [Double] = []
                source.frameHandler = { pts.append($0.metadata.presentationTime.seconds) }
                source.start(); spin { !pts.isEmpty }; pts.removeAll()
                player.rate = rate; pump(0.3); player.pause()
                let playback = pts
                XCTAssertFalse(playback.isEmpty, "\(fps)/\(requested)/\(rate)")
                XCTAssertEqual(playback.count, Set(playback).count, "自动播放不应重复提交 PTS：\(fps)/\(requested)/\(rate)")
                pump(0.05); source.pause(); pts.removeAll()
                for _ in 0..<2 { source.requestFrameUpdate(); source.refreshCurrentFrameIfNeeded() }
                XCTAssertEqual(pts.count, 2); XCTAssertEqual(pts.first, pts.last)
                var seeked = false
                source.seek(to: .zero) { seeked = $0 }; spin { seeked }
                spin { source.lastPresentationTime == .zero }
                let generation = source.snapshot.generation
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                spin { source.snapshot.generation > generation && source.lastPresentationTime == .zero }
                source.stop(); XCTAssertTrue(item.outputs.isEmpty)
                XCTAssertTrue(player.currentItem?.outputs.isEmpty == true)
                print("播放器矩阵 fps=\(fps) tick=\(requested) rate=\(rate) callbacks=\(playback.count) unique=\(Set(playback).count)")
            } }
        }
    }
}
#endif
