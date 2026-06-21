//
//  KakaposSurfaceGuide.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

/// A compact read-only guide for the four lightweight Kakapos boards.
///
/// This type does not add media behavior. It only packages the recommended
/// board order and its starter path into a single, easy-to-scan surface.
public struct KakaposSurfaceGuide: Sendable, Hashable, Codable {
    public let boards: [KakaposCapabilityBoardInfo]
    public let starterBoards: [KakaposCapabilityBoardInfo]

    public var boardCount: Int {
        boards.count
    }

    public var boardNames: [String] {
        boards.map(\.displayName)
    }

    public var starterBoardNames: [String] {
        starterBoards.map(\.displayName)
    }

    public var boardNamesText: String {
        boardNames.joined(separator: " · ")
    }

    public var starterBoardNamesText: String {
        starterBoardNames.joined(separator: " · ")
    }

    public var summaryText: String {
        "Kakapos keeps adoption lightweight with \(boardCount) boards: \(boardNamesText)."
    }

    public var starterText: String {
        "Start from \(starterBoardNamesText) when you only need the narrow read-only entry layer."
    }

    public init(
        boards: [KakaposCapabilityBoardInfo],
        starterBoards: [KakaposCapabilityBoardInfo]
    ) {
        self.boards = boards
        self.starterBoards = starterBoards
    }
}
