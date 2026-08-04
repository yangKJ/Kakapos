//
//  FrameProcessingPlan.swift
//  Kakapos
//
//  Created by Condy on 2026/8/4.
//

import Foundation

public struct FrameProcessingPlan: @unchecked Sendable {
    public struct Identity: Hashable, Sendable, Codable {
        public let identifier: String
        public let revision: String

        public init(identifier: String, revision: String) {
            self.identifier = identifier
            self.revision = revision
        }
    }

    public let identity: Identity
    private let processorFactory: () throws -> [FrameProcessor]

    public init(
        identity: Identity,
        makeProcessors: @escaping () throws -> [FrameProcessor]
    ) {
        self.identity = identity
        self.processorFactory = makeProcessors
    }

    public func makeProcessors() throws -> [FrameProcessor] {
        let processors = try processorFactory()
        guard processors.isEmpty == false else {
            throw FrameProcessingPlanError.emptyProcessorChain
        }
        return processors
    }
}

public enum FrameProcessingPlanError: Error, Equatable {
    case emptyProcessorChain
}
