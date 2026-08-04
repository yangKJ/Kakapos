//
//  Extensions.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation
import VideoToolbox

extension FileManager: KakaposCompatible { }
extension CVPixelBuffer: KakaposCompatible { }

extension KakaposWrapper where Base: FileManager {
    
    public func createURL(prefix: String = "", pathExtension: String = "mp4") throws -> URL {
        let documents = base.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let prefix_: String
        if prefix.isEmpty {
            prefix_ = UUID().uuidString
        } else {
            prefix_ = prefix + "_" + UUID().uuidString
        }
        let outputURL = documents.appendingPathComponent("\(prefix_).\(pathExtension)")
        // Check if the file already exists then remove the previous file
        if base.fileExists(atPath: outputURL.path) {
            try base.removeItem(at: outputURL)
        }
        return outputURL
    }
}
