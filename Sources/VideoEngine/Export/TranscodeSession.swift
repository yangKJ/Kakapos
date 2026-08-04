//
//  TranscodeSession.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import AVFoundation
import Foundation
import KakaposMediaCore

public struct VideoTranscodeConfiguration: @unchecked Sendable {
    public let outputURL: URL
    public let fileType: AVFileType
    public let timeRange: CMTimeRange?
    public let shouldOptimizeForNetworkUse: Bool
    public let durationTolerance: CMTime

    public init(
        outputURL: URL,
        fileType: AVFileType = .mp4,
        timeRange: CMTimeRange? = nil,
        shouldOptimizeForNetworkUse: Bool = true,
        durationTolerance: CMTime = CMTime(seconds: 0.12, preferredTimescale: 600)
    ) {
        self.outputURL = outputURL
        self.fileType = fileType
        self.timeRange = timeRange
        self.shouldOptimizeForNetworkUse = shouldOptimizeForNetworkUse
        self.durationTolerance = durationTolerance
    }
}

public struct VideoTranscodeRequest: @unchecked Sendable {
    public let asset: AVAsset
    public let plan: FrameProcessingPlan
    public let configuration: VideoTranscodeConfiguration

    public init(
        asset: AVAsset,
        plan: FrameProcessingPlan,
        configuration: VideoTranscodeConfiguration
    ) {
        self.asset = asset
        self.plan = plan
        self.configuration = configuration
    }
}

public struct ValidatedVideoArtifact: @unchecked Sendable {
    public let report: VideoArtifactValidationReport
    public let processingPlanIdentity: FrameProcessingPlan.Identity

    public var url: URL { report.url }
}

public final class TranscodeSession: @unchecked Sendable {
    public typealias ProgressHandler = (ReaderWriterExportJob.ProgressInfo) -> Void
    public typealias Completion = (Result<ValidatedVideoArtifact, Error>) -> Void

    public let planIdentity: FrameProcessingPlan.Identity
    private let request: VideoTranscodeRequest
    private var job: ReaderWriterExportJob?

    public init(request: VideoTranscodeRequest) {
        self.request = request
        planIdentity = request.plan.identity
    }

    public func start(
        progress: ProgressHandler? = nil,
        completion: @escaping Completion
    ) {
        do {
            let processors = try request.plan.makeProcessors()
            let sourceDuration = request.configuration.timeRange?.duration ?? request.asset.duration
            let expectation = VideoArtifactValidationExpectation(
                sourceDuration: sourceDuration,
                expectsAudio: request.asset.tracks(withMediaType: .audio).isEmpty == false,
                durationTolerance: request.configuration.durationTolerance
            )
            let job = ReaderWriterExportJob(
                asset: request.asset,
                outputURL: request.configuration.outputURL,
                fileType: request.configuration.fileType,
                timeRange: request.configuration.timeRange,
                videoProcessors: processors,
                shouldOptimizeForNetworkUse: request.configuration.shouldOptimizeForNetworkUse,
                artifactValidationExpectation: expectation
            )
            self.job = job
            job.progressHandler = progress
            job.export { [weak self] result in
                guard let self else { return }
                self.job = nil
                switch result {
                case let .success(url):
                    do {
                        let report = try VideoArtifactValidator.validate(url: url, expectation: expectation)
                        completion(.success(ValidatedVideoArtifact(
                            report: report,
                            processingPlanIdentity: self.planIdentity
                        )))
                    } catch {
                        completion(.failure(error))
                    }
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    public func cancel() {
        job?.cancel()
    }
}
