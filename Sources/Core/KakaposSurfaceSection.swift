//
//  KakaposSurfaceSection.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

/// Lightweight public sections for the four Kakapos entry points.
///
/// This type mirrors the capability catalog but gives external code a
/// smaller surface to scan when it only needs the recommended boards.
public struct KakaposSurfaceSection: Sendable, Hashable {
    public let board: KakaposCapabilityBoard
    public let displayName: String
    public let summary: String
    public let usageHint: String
    public let primaryTypes: [String]
    public let starterTypes: [String]

    public init(info: KakaposCapabilityBoardInfo) {
        self.board = info.board
        self.displayName = info.displayName
        self.summary = info.summary
        self.usageHint = info.usageHint
        self.primaryTypes = info.primaryTypes
        self.starterTypes = info.starterTypes
    }
}
