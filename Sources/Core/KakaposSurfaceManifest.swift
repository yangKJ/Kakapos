//
//  KakaposSurfaceManifest.swift
//  Kakapos
//
//  Created by Condy on 2026/6/22.
//

import Foundation

/// A compact serializable manifest for the four lightweight Kakapos boards.
///
/// This type exists so external tools can inspect the public surface without
/// pulling in the full media engine APIs.
public struct KakaposSurfaceManifest: Sendable, Hashable, Codable {
    public let boards: [KakaposSurfaceSection]
    public let starterBoards: [KakaposSurfaceSection]
    public let guide: KakaposSurfaceGuide

    public var boardCount: Int {
        boards.count
    }

    public var starterBoardCount: Int {
        starterBoards.count
    }

    public var boardNames: [String] {
        boards.map(\.displayName)
    }

    public var starterBoardNames: [String] {
        starterBoards.map(\.displayName)
    }

    public var summaryText: String {
        guide.summaryText
    }

    public var starterText: String {
        guide.starterText
    }

    public init(
        boards: [KakaposSurfaceSection],
        starterBoards: [KakaposSurfaceSection],
        guide: KakaposSurfaceGuide
    ) {
        self.boards = boards
        self.starterBoards = starterBoards
        self.guide = guide
    }
}
