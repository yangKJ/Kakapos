//
//  PlayerFrameSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

#if canImport(UIKit) || os(macOS)
public final class PlayerFrameSource: NSObject, MediaSource, MediaFrameSourceNode, MediaSourceSnapshotProviding {
    public struct Summary {
        public let state: State
        public let generation: Int64
        public let frameIndex: Int64
        public let hasLastFrame: Bool
        public let hasSeekTarget: Bool
        public let lastFrameRequestReason: String?
        public let lastPresentationTime: CMTime?
        public let lastPlayerItemTime: CMTime?
        public let preferredFramesPerSecond: Int
        public let lastErrorDescription: String?

        public var summaryText: String {
            var text = "state \(state) · generation \(generation) · frame \(frameIndex) · lastFrame \(hasLastFrame ? "yes" : "no") · seekTarget \(hasSeekTarget ? "yes" : "no") · fps \(preferredFramesPerSecond)"
            if let lastFrameRequestReason {
                text += " · reason \(lastFrameRequestReason)"
            }
            if let lastPresentationTime {
                text += " · presentation \(String(format: "%.2fs", lastPresentationTime.seconds))"
            }
            if let lastPlayerItemTime {
                text += " · itemTime \(String(format: "%.2fs", lastPlayerItemTime.seconds))"
            }
            if let lastErrorDescription {
                text += " · error \(lastErrorDescription)"
            }
            return text
        }
    }

    public struct Snapshot {
        public let state: State
        public let generation: Int64
        public let frameIndex: Int64
        public let hasLastFrame: Bool
        public let hasSeekTarget: Bool
        public let lastFrameRequestReason: String?
        public let lastPresentationTime: CMTime?
        public let lastPlayerItemTime: CMTime?
        public let preferredFramesPerSecond: Int
        public let lastErrorDescription: String?
    }

    public enum State: Equatable {
        case idle
        case active
        case paused
        case waitingForMediaData
        case finished
    }

    public enum MetadataKey {
        public static let playerItemTime = "kakapos.player-item-time"
        public static let playerRate = "kakapos.player-rate"
        public static let playbackState = "kakapos.playback-state"
        public static let generation = "kakapos.player-generation"
        public static let frameRequestReason = "kakapos.player-frame-request-reason"
        public static let seekTargetTime = "kakapos.player-seek-target-time"
    }

    public weak var delegate: MediaSourceDelegate?
    public let player: AVPlayer
    public private(set) var state: State = .idle
    public private(set) var lastFrame: MediaFrame?
    public private(set) var lastSeekTargetTime: CMTime?
    public private(set) var lastFrameRequestReason: String?
    public private(set) var lastPresentationTime: CMTime?
    public private(set) var lastPlayerItemTime: CMTime?
    public private(set) var lastErrorDescription: String?
    public var frameHandler: ((MediaFrame) -> Void)?
    public var stateChangedHandler: ((State) -> Void)?
    public var itemChangedHandler: ((AVPlayerItem?) -> Void)?
    public var preferredFramesPerSecond: Int {
        didSet {
            driver?.configuration.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    public var snapshot: Snapshot {
        Snapshot(
            state: state,
            generation: coordinator.generation,
            frameIndex: coordinator.frameIndex,
            hasLastFrame: lastFrame != nil,
            hasSeekTarget: lastSeekTargetTime != nil,
            lastFrameRequestReason: lastFrameRequestReason,
            lastPresentationTime: lastPresentationTime,
            lastPlayerItemTime: lastPlayerItemTime,
            preferredFramesPerSecond: preferredFramesPerSecond,
            lastErrorDescription: lastErrorDescription
        )
    }

    public var summary: Summary {
        let currentSnapshot = snapshot
        return Summary(
            state: currentSnapshot.state,
            generation: currentSnapshot.generation,
            frameIndex: currentSnapshot.frameIndex,
            hasLastFrame: currentSnapshot.hasLastFrame,
            hasSeekTarget: currentSnapshot.hasSeekTarget,
            lastFrameRequestReason: currentSnapshot.lastFrameRequestReason,
            lastPresentationTime: currentSnapshot.lastPresentationTime,
            lastPlayerItemTime: currentSnapshot.lastPlayerItemTime,
            preferredFramesPerSecond: currentSnapshot.preferredFramesPerSecond,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
    }

    public var summaryText: String {
        var text = summary.summaryText
        text += " · sourceSnapshot \(sourceSnapshot.summaryText)"
        return text
    }

    public var sourceSnapshot: MediaSourceSnapshot {
        MediaSourceSnapshot(
            stateDescription: String(describing: summary.state),
            lastFrameIndex: summary.frameIndex > 0 ? summary.frameIndex : nil,
            lastPresentationTime: summary.lastPresentationTime,
            lastSourceTime: summary.lastPlayerItemTime,
            lastErrorDescription: summary.lastErrorDescription,
            details: [
                "generation": "\(summary.generation)",
                "fps": "\(summary.preferredFramesPerSecond)",
                "reason": summary.lastFrameRequestReason ?? "n/a",
                "playerRate": Self.timeText(player.rate),
                "itemTime": Self.timeText(summary.lastPlayerItemTime),
                "playbackState": String(describing: coordinator.playbackState),
                "seekTarget": summary.hasSeekTarget ? "yes" : "no",
                "seekTargetTime": Self.timeText(lastSeekTargetTime),
                "lastFrame": summary.hasLastFrame ? "yes" : "no"
            ]
        )
    }

    private var coordinator = PlayerFrameCoordinator()
    private var currentItemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeJumpObserver: NSObjectProtocol?
    private var driver: PlayerFrameDriving?
    private let outputNode = MediaOutputNode()
    private let driverFactory: (AVPlayer, PlayerFrameOutputDriver.Configuration, @escaping (PlayerFrameOutputDriver.VideoFrame) -> Void) -> PlayerFrameDriving
    private let lifecycleLock = NSLock()
    private var acceptsFrames = true

    public init(player: AVPlayer, preferredFramesPerSecond: Int = 30) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.driverFactory = { player, configuration, handler in
            PlayerFrameOutputDriver(player: player, configuration: configuration, handler: handler)
        }
        super.init()
    }

    init(
        player: AVPlayer,
        preferredFramesPerSecond: Int = 30,
        driverFactory: @escaping (AVPlayer, PlayerFrameOutputDriver.Configuration, @escaping (PlayerFrameOutputDriver.VideoFrame) -> Void) -> PlayerFrameDriving
    ) {
        self.player = player
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.driverFactory = driverFactory
        super.init()
    }

    deinit {
        invalidateObservers()
    }

    public func start() {
        resetFrameAcceptance()
        observePlayerIfNeeded()
        lastSeekTargetTime = nil
        lastFrame = nil
        lastFrameRequestReason = nil
        lastPresentationTime = nil
        lastPlayerItemTime = nil
        lastErrorDescription = nil
        _ = coordinator.start(with: player.currentItem)
        updateState(from: coordinator.playbackState)
        lastFrameRequestReason = "playback"
        itemChangedHandler?(player.currentItem)
        observeAttachedItem(player.currentItem)
        ensureDriver()
        driver?.setNeedsUpdate()
    }

    public func pause() {
        coordinator.pause()
        updateState(from: coordinator.playbackState)
    }

    public func resume() {
        coordinator.resume()
        updateState(from: coordinator.playbackState)
        driver?.setNeedsUpdate()
    }

    public func stop() {
        rejectFurtherFrames()
        coordinator.stop()
        updateState(from: coordinator.playbackState)
        lastSeekTargetTime = nil
        lastFrameRequestReason = nil
        lastPresentationTime = nil
        lastPlayerItemTime = nil
        lastErrorDescription = nil
        invalidateObservers()
        delegate?.mediaSourceDidFinish(self)
    }

    public func cancel() {
        stop()
    }

    public func requestFrameUpdate() {
        driver?.setNeedsUpdate()
    }

    public func refreshCurrentFrameIfNeeded() {
        driver?.updateIfNeeded()
    }

    public func seek(
        to time: CMTime,
        toleranceBefore: CMTime = .zero,
        toleranceAfter: CMTime = .zero,
        completion: ((Bool) -> Void)? = nil
    ) {
        lastSeekTargetTime = time
        lastFrame = nil
        lastFrameRequestReason = nil
        player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] finished in
            guard let self else {
                completion?(finished)
                return
            }
            if finished {
                self.coordinator.resume()
                self.updateState(from: self.coordinator.playbackState)
                self.driver?.setNeedsUpdate()
                self.driver?.updateIfNeeded()
            }
            completion?(finished)
        }
    }

    private func ensureDriver() {
        if let driver {
            driver.configuration.preferredFramesPerSecond = preferredFramesPerSecond
            driver.setNeedsUpdate()
            return
        }

        let configuration = PlayerFrameOutputDriver.Configuration(
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA],
            preferredFramesPerSecond: preferredFramesPerSecond
        )
        let driver = driverFactory(player, configuration) { [weak self] frame in
            self?.handleVideoFrame(frame)
        }
        driver.waitingForMediaDataHandler = { [weak self] _ in
            guard let self else { return }
            if self.coordinator.beginWaitingForMediaData() {
                self.updateState(from: self.coordinator.playbackState)
            }
        }
        driver.mediaDataWillChangeHandler = { [weak self] in
            guard let self else { return }
            if self.coordinator.mediaDataWillChange() {
                self.updateState(from: self.coordinator.playbackState)
            }
        }
        self.driver = driver
    }

    private func handleVideoFrame(_ frame: PlayerFrameOutputDriver.VideoFrame) {
        guard canAcceptFrames() else { return }
        guard coordinator.shouldDriveDisplayLink || player.rate == 0 else { return }
        let frameIndex = coordinator.markFrameOutput()
        updateState(from: coordinator.playbackState)
        let seekTargetTime = lastSeekTargetTime
        let presentationTime = frame.presentationTimestamp
        let playerItemTime = frame.playerTimestamp
        var userInfo: [String: Any] = [
            MetadataKey.playerItemTime: frame.requestTimestamp,
            MetadataKey.playerRate: player.rate,
            MetadataKey.playbackState: String(describing: coordinator.playbackState),
            MetadataKey.generation: coordinator.generation
        ]
        if let seekTargetTime {
            let didReachSeekTarget = CMTimeCompare(frame.requestTimestamp, seekTargetTime) == 0
                || CMTimeCompare(presentationTime, seekTargetTime) == 0
                || CMTimeCompare(playerItemTime, seekTargetTime) == 0
            userInfo[MetadataKey.seekTargetTime] = seekTargetTime
            userInfo[MetadataKey.frameRequestReason] = "seek"
            lastFrameRequestReason = "seek"
            if didReachSeekTarget {
                lastSeekTargetTime = nil
            }
        } else if player.rate == 0 {
            userInfo[MetadataKey.frameRequestReason] = "manual"
            lastFrameRequestReason = "manual"
        } else {
            userInfo[MetadataKey.frameRequestReason] = "playback"
            lastFrameRequestReason = "playback"
        }
        lastPresentationTime = presentationTime
        lastPlayerItemTime = frame.requestTimestamp
        let metadata = FrameMetadata(
            presentationTime: presentationTime,
            sourceTime: playerItemTime,
            trackTransform: frame.preferredTrackTransform,
            frameIndex: frameIndex,
            userInfo: userInfo
        )
        let mediaFrame = MediaFrame(pixelBuffer: frame.pixelBuffer, metadata: metadata)
        lastFrame = mediaFrame
        frameHandler?(mediaFrame)
        delegate?.mediaSource(self, didOutput: mediaFrame)
        outputNode.transmit(mediaFrame) { _ in }
    }

    private func observePlayerIfNeeded() {
        guard currentItemObservation == nil else { return }
        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            self?.handleCurrentItemChange(change.newValue ?? nil)
        }
    }

    private func handleCurrentItemChange(_ item: AVPlayerItem?) {
        let didChange = coordinator.updateCurrentItem(item)
        if didChange {
            lastSeekTargetTime = nil
            lastFrame = nil
            lastFrameRequestReason = nil
            lastPresentationTime = nil
            lastPlayerItemTime = nil
            lastErrorDescription = nil
        }
        itemChangedHandler?(item)
        observeAttachedItem(item)
        if didChange {
            coordinator.resume()
            updateState(from: coordinator.playbackState)
            lastFrameRequestReason = "playback"
            driver?.setNeedsUpdate()
        }
    }

    private func observeAttachedItem(_ item: AVPlayerItem?) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        guard let item else { return }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.coordinator.stop()
            self.updateState(from: self.coordinator.playbackState)
            self.delegate?.mediaSourceDidFinish(self)
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                ?? NSError(domain: "com.condy.kakapos.player-frame-source", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player item failed to play to end time."])
            self.handlePlayerItemFailure(error)
        }
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.coordinator.resume()
            self.updateState(from: self.coordinator.playbackState)
            self.driver?.setNeedsUpdate()
        }
    }

    private func handlePlayerItemFailure(_ error: Error) {
        lastErrorDescription = Self.errorDescription(for: error)
        rejectFurtherFrames()
        coordinator.stop()
        updateState(from: coordinator.playbackState)
        delegate?.mediaSource(self, didFail: error)
    }

    private func invalidateObservers() {
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
        driver = nil
    }

    private func updateState(from playbackState: PlayerFramePlaybackState) {
        let nextState: State
        switch playbackState {
        case .idle:
            nextState = .idle
        case .running:
            nextState = .active
        case .paused:
            nextState = .paused
        case .waitingForMediaData:
            nextState = .waitingForMediaData
        case .finished:
            nextState = .finished
        }
        guard state != nextState else { return }
        state = nextState
        stateChangedHandler?(nextState)
    }

    private static func errorDescription(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    private func resetFrameAcceptance() {
        lifecycleLock.lock()
        acceptsFrames = true
        lifecycleLock.unlock()
    }

    private func rejectFurtherFrames() {
        lifecycleLock.lock()
        acceptsFrames = false
        lifecycleLock.unlock()
    }

    private func canAcceptFrames() -> Bool {
        lifecycleLock.lock()
        let result = acceptsFrames
        lifecycleLock.unlock()
        return result
    }

    @discardableResult
    public func add<T: MediaFrameConsumerNode>(consumer: T) -> T {
        outputNode.add(consumer: consumer)
    }

    public func add(consumer: MediaFrameConsumerNode, at index: Int) {
        outputNode.add(consumer: consumer, at: index)
    }

    public func remove(consumer: MediaFrameConsumerNode) {
        outputNode.remove(consumer: consumer)
    }

    public func removeAllConsumers() {
        outputNode.removeAllConsumers()
    }

    private static func timeText(_ time: CMTime?) -> String {
        guard let time, time.isNumeric else {
            return "n/a"
        }
        return String(format: "%.2fs", time.seconds)
    }

    private static func timeText(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}
#endif
