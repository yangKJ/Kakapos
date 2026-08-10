//
//  Components/ExampleSharedViews.swift
//  KakaposExamples
//
//  Created by Condy on 2026/6/22.
//

import Kakapos
import SwiftUI

struct BoardHeaderView: View {
    let board: KakaposCapabilityBoard

    private var entry: KakaposSurface.Entry? {
        KakaposSurface.entry(board)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry?.displayName ?? board.displayName)
                    .font(.headline)
                Text(entry?.starterTypesText ?? board.starterTypes.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(entry?.summary ?? board.summary)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
