//
//  ExporterCommand.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

public protocol ExporterCommand {
    func execute(export: AVAssetExportSession)
}
