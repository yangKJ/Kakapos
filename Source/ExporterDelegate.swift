//
//  ExporterDelegate.swift
//  Exporter
//
//  Created by Condy on 2022/12/20.
//

import Foundation

public protocol ExporterDelegate: NSObjectProtocol {
    
    /// Video export successed.
    /// - Parameters:
    ///   - exporter: Exporter
    ///   - videoURL: Export the successful video url, Be equivalent to outputURL.
    func export(_ exporter: Exporter, success videoURL: URL)
    
    /// Video export failure.
    /// - Parameters:
    ///   - exporter: Exporter
    ///   - error: Failure error message.
    func export(_ exporter: Exporter, failed error: Exporter.Error)
}
