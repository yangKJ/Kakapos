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
            completion(result)
            if case .success = result {
                self?.completionHandler?()
            }
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
        case finishing
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

    private var pipelineErrorHandler: ((Error) -> Void)?
    public var errorHandler: ((Error) -> Void)? {
        get { stateQueue.sync { pipelineErrorHandler } }
        set { stateQueue.sync { pipelineErrorHandler = newValue } }
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
    private var terminalResult: Result<Void, Error>?
    private var stopCompletions: [(Result<Void, Error>) -> Void] = []
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
        controlsSourceLifecycle: Bool = true,
        maximumInFlightAudioFrameCount: Int? = nil,
        processesAudioFrames: Bool = true
    ) {
        self.source = source
        self.chain = MediaProcessorChain(processors: processors, sinks: sinks)
        self.sourceAdapter = MediaSourceNodeAdapter(source: source)
        self.controlsSourceLifecycle = controlsSourceLifecycle
        self.chain.node.processorNode.processesAudioFrames = processesAudioFrames
        self.sourceAdapter.maximumInFlightAudioFrameCount = maximumInFlightAudioFrameCount.map { max(1, $0) }
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
        guard state == .running else { return }
        if controlsSourceLifecycle {
            source.pause()
        }
        chain.pause()
        transitionIfNeeded(from: [.running], to: .paused)
    }

    public func resume() {
        guard state == .paused else { return }
        if controlsSourceLifecycle {
            source.resume()
        }
        chain.resume()
        transitionIfNeeded(from: [.paused], to: .running)
    }

    public func stop() {
        guard transitionIfNeeded(from: [.idle, .running, .paused], to: .finishing) else { return }
        rejectFurtherSourceCallbacks()
        if controlsSourceLifecycle { source.stop() }
        markSourceFinished()
    }

    /// 完成所有已接纳帧与 sink 收尾后，在主线程回传唯一终态结果。
    public func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        let result = stateQueue.sync { () -> Result<Void, Error>? in
            if let terminalResult { return terminalResult }
            // 请求持有管线到终态，宿主释放引用也不能丢失已登记的完成回调。
            stopCompletions.append { [self] result in withExtendedLifetime(self) { completion(result) } }
            return nil
        }
        if let result {
            deliverStopCompletions([completion], result: result)
        } else {
            stop()
        }
    }

    public func cancel() {
        guard transitionIfNeeded(from: [.idle, .running, .paused, .finishing], to: .cancelled) else { return }
        rejectFurtherSourceCallbacks()
        if controlsSourceLifecycle { source.cancel() }
        chain.cancel()
        completeTerminal(.failure(MediaCoreError.processingCancelled))
    }

    private func finishChain() {
        markSourceFinished()
    }

    private func failChain(with error: Error, cancelChain: Bool = true) {
        let errorDescription = Self.errorDescription(for: error)
        let allowedStates: [State] = [.running, .paused, .idle, .finishing]
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
        completeTerminal(.failure(error))
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
        let shouldFinish = stateQueue.sync { () -> Bool in
            guard [.idle, .running, .paused, .finishing].contains(_state), !hasFinished else { return false }
            hasFinished = true
            return true
        }
        guard shouldFinish else { return }
        _ = transitionIfNeeded(from: [.idle, .running, .paused], to: .finishing)
        rejectFurtherSourceCallbacks()
        chain.finish { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                guard self.transitionIfNeeded(from: [.finishing], to: .finished) else { return }
                self.completeTerminal(.success(()))
            case .failure(let error):
                self.failChain(with: error, cancelChain: false)
            }
        }
    }

    private func completeTerminal(_ result: Result<Void, Error>) {
        let completions = stateQueue.sync { () -> [(Result<Void, Error>) -> Void] in
            guard terminalResult == nil else { return [] }
            terminalResult = result
            let completions = stopCompletions
            stopCompletions.removeAll()
            return completions
        }
        deliverStopCompletions(completions, result: result)
    }

    private func deliverStopCompletions(_ completions: [(Result<Void, Error>) -> Void], result: Result<Void, Error>) {
        let transfer = UnsafeSendableBox(value: (completions, result))
        DispatchQueue.main.async { transfer.value.0.forEach { $0(transfer.value.1) } }
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
