//
//  MediaPipeline.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation

public final class MediaProcessorChain: MediaSink {
    public var processors: [FrameProcessor] {
        get { node.processors }
        set { node.processors = newValue }
    }

    public var sinks: [MediaSink] {
        get { node.sinks }
        set { node.sinks = newValue }
    }

    public var errorHandler: ((Error) -> Void)? {
        get { node.errorHandler }
        set { node.errorHandler = newValue }
    }

    public var completionHandler: (() -> Void)?

    public var summary: MediaProcessorChainSummary {
        MediaProcessorChainSummary(
            processorTypeNames: processors.map { String(describing: type(of: $0)) },
            sinkTypeNames: sinks.map { String(describing: type(of: $0)) }
        )
    }

    let node: MediaConsumerChainNode

    public init(processors: [FrameProcessor] = [], sinks: [MediaSink] = []) {
        self.node = MediaConsumerChainNode(processors: processors, sinks: sinks)
    }

    public func consume(_ frame: MediaFrame, completion: @escaping (Result<Void, Error>) -> Void) {
        node.consume(frame, from: node, completion: completion)
    }

    public func pause() {
        node.pause()
    }

    public func resume() {
        node.resume()
    }

    public func cancel() {
        node.cancel()
    }

    public func finish(completion: @escaping (Result<Void, Error>) -> Void) {
        node.finish { [weak self] result in
            if case .success = result {
                self?.completionHandler?()
            }
            completion(result)
        }
    }
}

/// 单次运行的媒体管线。`finished`、`cancelled` 和 `failed` 都是不可逆终态；
/// 新一轮处理必须创建新的管线、处理链和 sink。
public final class MediaPipeline: @unchecked Sendable {

    fileprivate struct UnsafeSendableBox<T>: @unchecked Sendable {
        let value: T
    }
    public enum State: Equatable {
        case idle
        case running
        case paused
        case finished
        case cancelled
        case failed
    }

    public struct Snapshot {
        public let sourceTypeName: String
        public let processorTypeNames: [String]
        public let sinkTypeNames: [String]
        public let state: State
        public let sourceSnapshot: MediaSourceSnapshot?
        public let lastFrameMetadata: FrameMetadata?
        public let lastErrorDescription: String?
    }

    public struct ManifestSourceSnapshot: Equatable, Sendable, Codable {
        public let stateDescription: String
        public let lastFrameIndex: Int64?
        public let lastPresentationTimeSeconds: Double?
        public let lastSourceTimeSeconds: Double?
        public let lastErrorDescription: String?
        public let details: [String: String]

        public init(snapshot: MediaSourceSnapshot) {
            self.stateDescription = snapshot.stateDescription
            self.lastFrameIndex = snapshot.lastFrameIndex
            self.lastPresentationTimeSeconds = snapshot.lastPresentationTime?.seconds
            self.lastSourceTimeSeconds = snapshot.lastSourceTime?.seconds
            self.lastErrorDescription = snapshot.lastErrorDescription
            self.details = snapshot.details
        }
    }

    public struct ManifestFrameMetadata: Equatable, Sendable, Codable {
        public let presentationTimeSeconds: Double
        public let durationSeconds: Double?
        public let sourceTimeSeconds: Double?
        public let trackTransformA: Double
        public let trackTransformB: Double
        public let trackTransformC: Double
        public let trackTransformD: Double
        public let trackTransformTX: Double
        public let trackTransformTY: Double
        public let frameIndex: Int64?

        public init(metadata: FrameMetadata) {
            self.presentationTimeSeconds = metadata.presentationTime.seconds
            self.durationSeconds = metadata.duration?.seconds
            self.sourceTimeSeconds = metadata.sourceTime?.seconds
            self.trackTransformA = Double(metadata.trackTransform.a)
            self.trackTransformB = Double(metadata.trackTransform.b)
            self.trackTransformC = Double(metadata.trackTransform.c)
            self.trackTransformD = Double(metadata.trackTransform.d)
            self.trackTransformTX = Double(metadata.trackTransform.tx)
            self.trackTransformTY = Double(metadata.trackTransform.ty)
            self.frameIndex = metadata.frameIndex
        }
    }

    public struct Manifest: Equatable, Sendable, Codable {
        public let sourceTypeName: String
        public let processorTypeNames: [String]
        public let sinkTypeNames: [String]
        public let stateDescription: String
        public let sourceSnapshot: ManifestSourceSnapshot?
        public let lastFrameMetadata: ManifestFrameMetadata?
        public let lastErrorDescription: String?
    }

    public let source: MediaSource
    public let chain: MediaProcessorChain
    public var state: State {
        stateQueue.sync { _state }
    }

    public var stateHandler: ((State) -> Void)?

    public var processors: [FrameProcessor] {
        get { chain.processors }
        set { chain.processors = newValue }
    }

    public var sinks: [MediaSink] {
        get { chain.sinks }
        set { chain.sinks = newValue }
    }

    public var snapshot: Snapshot {
        let runtimeState = stateQueue.sync {
            (state: _state, metadata: _lastFrameMetadata, error: _lastErrorDescription)
        }
        return Snapshot(
            sourceTypeName: String(describing: type(of: source)),
            processorTypeNames: processors.map { String(describing: type(of: $0)) },
            sinkTypeNames: sinks.map { String(describing: type(of: $0)) },
            state: runtimeState.state,
            sourceSnapshot: (source as? MediaSourceSnapshotProviding)?.sourceSnapshot,
            lastFrameMetadata: runtimeState.metadata,
            lastErrorDescription: runtimeState.error
        )
    }

    public var summary: MediaPipelineSummary {
        let currentSnapshot = snapshot
        return MediaPipelineSummary(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorTypeNames: currentSnapshot.processorTypeNames,
            sinkTypeNames: currentSnapshot.sinkTypeNames,
            state: currentSnapshot.state,
            sourceSnapshot: currentSnapshot.sourceSnapshot,
            lastFrameIndex: currentSnapshot.lastFrameMetadata?.frameIndex,
            lastPresentationTime: currentSnapshot.lastFrameMetadata?.presentationTime,
            lastSourceTime: currentSnapshot.lastFrameMetadata?.sourceTime,
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
    }

    public var manifest: Manifest {
        let currentSnapshot = snapshot
        return Manifest(
            sourceTypeName: currentSnapshot.sourceTypeName,
            processorTypeNames: currentSnapshot.processorTypeNames,
            sinkTypeNames: currentSnapshot.sinkTypeNames,
            stateDescription: String(describing: currentSnapshot.state),
            sourceSnapshot: currentSnapshot.sourceSnapshot.map(ManifestSourceSnapshot.init(snapshot:)),
            lastFrameMetadata: currentSnapshot.lastFrameMetadata.map(ManifestFrameMetadata.init(metadata:)),
            lastErrorDescription: currentSnapshot.lastErrorDescription
        )
    }

    public var lastFrameMetadata: FrameMetadata? {
        stateQueue.sync { _lastFrameMetadata }
    }

    public var lastErrorDescription: String? {
        stateQueue.sync { _lastErrorDescription }
    }

    public var droppedSourceFrameCount: Int {
        stateQueue.sync { _droppedSourceFrameCount }
    }

    public var errorHandler: ((Error) -> Void)? {
        get { chain.errorHandler }
        set { chain.errorHandler = newValue }
    }

    public var completionHandler: (() -> Void)? {
        get { chain.completionHandler }
        set {
            chain.completionHandler = newValue
            sourceAdapter.finishHandler = { [weak self] in
                self?.finishChain()
            }
        }
    }

    private let sourceAdapter: MediaSourceNodeAdapter
    private let controlsSourceLifecycle: Bool
    private let stateQueue = DispatchQueue(label: "com.condy.kakapos.media-pipeline.state")
    private let lifecycleLock = NSLock()
    private var hasFinished = false
    private var acceptsSourceCallbacks = false
    private var pendingSourceFrameDeliveries = 0
    private var sourceFrameCompletionsInProgress = 0
    private var sourceDidFinish = false
    private var _state: State = .idle
    private var _lastFrameMetadata: FrameMetadata?
    private var _lastErrorDescription: String?
    private var _droppedSourceFrameCount = 0

    public init(
        source: MediaSource,
        processors: [FrameProcessor] = [],
        sinks: [MediaSink] = [],
        deliveryPolicy: MediaSourceDeliveryPolicy = .unbounded,
        controlsSourceLifecycle: Bool = true
    ) {
        self.source = source
        self.chain = MediaProcessorChain(processors: processors, sinks: sinks)
        self.sourceAdapter = MediaSourceNodeAdapter(source: source)
        self.controlsSourceLifecycle = controlsSourceLifecycle
        self.sourceAdapter.deliveryPolicy = deliveryPolicy
        self.sourceAdapter.add(consumer: chain.node)
        self.sourceAdapter.shouldAcceptSourceCallbacks = { [weak self] in
            self?.canAcceptSourceCallbacks() ?? false
        }
        self.sourceAdapter.finishHandler = { [weak self] in
            self?.finishChain()
        }
        self.sourceAdapter.frameHandler = { [weak self] frame in
            guard let self, self.canAcceptSourceCallbacks() else { return }
            self.storeLastFrameMetadata(frame.metadata)
        }
        self.sourceAdapter.sourceFrameAcceptanceHandler = { [weak self] in
            self?.beginSourceFrameDeliveryIfAccepted() ?? false
        }
        self.sourceAdapter.frameTransmissionCompletedHandler = { [weak self] result in
            self?.completeSourceFrameDelivery(result)
        }
        self.sourceAdapter.droppedFrameHandler = { [weak self] _ in
            self?.recordDroppedSourceFrame()
        }
        self.sourceAdapter.errorHandler = { [weak self] error in
            guard let self, self.canAcceptSourceCallbacks() else { return }
            self.failChain(with: error)
        }
    }

    public convenience init(source: MediaSource, branch: MediaGraphBranch) {
        self.init(source: source, processors: branch.processors, sinks: branch.sinks)
    }

    public func start() {
        guard canStart(), sourceAdapter.prepareForStartIfIdle() else { return }
        guard transitionIfNeeded(from: [.idle], to: .running) else { return }
        resetLifecycleState()
        resetSourceCallbacksAcceptance()
        if controlsSourceLifecycle {
            source.start()
        }
    }

    public func pause() {
        if controlsSourceLifecycle {
            source.pause()
        }
        chain.pause()
        transitionIfNeeded(from: [.running], to: .paused)
    }

    public func resume() {
        if controlsSourceLifecycle {
            source.resume()
        }
        chain.resume()
        transitionIfNeeded(from: [.paused], to: .running)
    }

    public func stop() {
        guard canStop() else { return }
        rejectFurtherSourceCallbacks()
        if controlsSourceLifecycle {
            source.stop()
        }
        markSourceFinished()
    }

    public func cancel() {
        rejectFurtherSourceCallbacks()
        transitionIfNeeded(from: [.idle, .running, .paused], to: .cancelled)
        if controlsSourceLifecycle {
            source.cancel()
        }
        chain.cancel()
    }

    private func finishChain() {
        markSourceFinished()
    }

    private func failChain(with error: Error, allowFromFinished: Bool = false, cancelChain: Bool = true) {
        let errorDescription = Self.errorDescription(for: error)
        var allowedStates: [State] = [.running, .paused, .idle]
        if allowFromFinished {
            allowedStates.append(.finished)
        }
        guard transitionIfNeeded(from: allowedStates, to: .failed) else { return }
        stateQueue.sync {
            _lastErrorDescription = errorDescription
        }
        rejectFurtherSourceCallbacks()
        if controlsSourceLifecycle {
            source.cancel()
        }
        if cancelChain {
            chain.cancel()
        }
        DispatchQueue.main.async {
            self.errorHandler?(error)
        }
    }

    private func beginSourceFrameDeliveryIfAccepted() -> Bool {
        stateQueue.sync {
            guard _state == .running || _state == .paused else { return false }
            pendingSourceFrameDeliveries += 1
            return true
        }
    }

    private func completeSourceFrameDelivery(_ result: Result<Void, Error>) {
        let shouldFinish = stateQueue.sync { () -> Bool in
            sourceFrameCompletionsInProgress += 1
            if pendingSourceFrameDeliveries > 0 {
                pendingSourceFrameDeliveries -= 1
            }
            return sourceDidFinish && pendingSourceFrameDeliveries == 0
        }
        defer {
            stateQueue.sync {
                sourceFrameCompletionsInProgress = max(0, sourceFrameCompletionsInProgress - 1)
            }
        }

        if case .failure(let error) = result {
            failChain(with: error)
            return
        }

        if shouldFinish {
            finishChainIfPossible()
        }
    }

    private func markSourceFinished() {
        let shouldFinish = stateQueue.sync { () -> Bool in
            sourceDidFinish = true
            return pendingSourceFrameDeliveries == 0
        }
        if shouldFinish {
            finishChainIfPossible()
        }
    }

    private func finishChainIfPossible() {
        guard transitionIfNeeded(from: [.running, .paused, .idle], to: .finished) else { return }
        rejectFurtherSourceCallbacks()
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }

        chain.finish { [weak self] result in
            if case .failure(let error) = result {
                self?.failChain(with: error, allowFromFinished: true, cancelChain: false)
            }
        }
    }

    private func storeLastFrameMetadata(_ metadata: FrameMetadata) {
        stateQueue.sync {
            _lastFrameMetadata = metadata
        }
    }

    private func recordDroppedSourceFrame() {
        stateQueue.sync {
            _droppedSourceFrameCount += 1
        }
    }

    private func resetLifecycleState() {
        stateQueue.sync {
            hasFinished = false
            sourceDidFinish = false
            pendingSourceFrameDeliveries = 0
            sourceFrameCompletionsInProgress = 0
            _lastFrameMetadata = nil
            _lastErrorDescription = nil
            _droppedSourceFrameCount = 0
        }
    }

    private func canStart() -> Bool {
        stateQueue.sync {
            _state == .idle
                && pendingSourceFrameDeliveries == 0
                && sourceFrameCompletionsInProgress == 0
        }
    }

    private func canStop() -> Bool {
        stateQueue.sync {
            _state != .finished && _state != .cancelled && _state != .failed
        }
    }

    private func resetSourceCallbacksAcceptance() {
        lifecycleLock.lock()
        acceptsSourceCallbacks = true
        lifecycleLock.unlock()
    }

    private func rejectFurtherSourceCallbacks() {
        lifecycleLock.lock()
        acceptsSourceCallbacks = false
        lifecycleLock.unlock()
    }

    private func canAcceptSourceCallbacks() -> Bool {
        lifecycleLock.lock()
        let acceptsCallbacks = acceptsSourceCallbacks
        lifecycleLock.unlock()
        guard acceptsCallbacks else { return false }
        return stateQueue.sync {
            _state == .running || _state == .paused
        }
    }

    @discardableResult
    private func transitionIfNeeded(from allowedStates: [State]?, to newState: State) -> Bool {
        let didChange = stateQueue.sync { () -> Bool in
            if let allowedStates, !allowedStates.contains(_state) {
                return false
            }
            guard _state != newState else { return false }
            _state = newState
            return true
        }
        guard didChange else { return false }
        let selfBox = UnsafeSendableBox(value: self)
        let newStateBox = UnsafeSendableBox(value: newState)
        DispatchQueue.main.async {
            selfBox.value.stateHandler?(newStateBox.value)
        }
        return true
    }

    private static func errorDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain != NSCocoaErrorDomain {
            return "\(nsError.domain)#\(nsError.code)"
        }
        return nsError.localizedDescription
    }
}

public extension MediaPipeline {
    func makeBranch(children: [MediaGraphBranch] = []) -> MediaGraphBranch {
        MediaGraphBranch(
            processors: processors,
            sinks: sinks,
            children: children
        )
    }
}
