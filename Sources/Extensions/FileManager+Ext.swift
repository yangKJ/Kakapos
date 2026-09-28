//
//  FileManager+Ext.swift
//  KakaposExamples
//
//  Created by Condy on 2024/2/29.
//

import Foundation

extension KakaposWrapper where Base: FileManager {
    
    public func createURL(prefix: String, pathExtension: String = "mp4") throws -> URL {
        let documents = base.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let random = Int(Date().timeIntervalSince1970/2)
        let outputURL = documents.appendingPathComponent("\(prefix)_\(random).\(pathExtension)")
        // Check if the file already exists then remove the previous file
        if base.fileExists(atPath: outputURL.path) {
            try base.removeItem(at: outputURL)
        }
        return outputURL
    }
}
