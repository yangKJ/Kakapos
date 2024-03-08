//
//  ExporterError.swift
//  Kakapos
//
//  Created by Condy on 2022/12/20.
//

import Foundation
import AVFoundation

extension Exporter {
    /// Exporter error definition.
    public enum Error: Swift.Error {
        case unknown
        case error(Swift.Error)
        case videoTrackEmpty
        case addVideoTrack
        case exportSessionEmpty
        case exportAsynchronously(AVAssetExportSession.Status)
        case exportCancelled
        case unsupportedFileType
    }
}

extension Exporter.Error: CustomStringConvertible, CustomNSError {
    
    /// For each error type return the appropriate description.
    public var description: String {
        localizedDescription
    }
    
    public var errorDescription: String? {
        localizedDescription
    }
    
    /// A textual representation of `self`, suitable for debugging.
    public var localizedDescription: String {
        switch self {
        case .unknown:
            return "Unknown error occurred."
        case .error(let error):
            return error.localizedDescription
        case .videoTrackEmpty:
            return "Video track is nil."
        case .exportSessionEmpty:
            return "Video asset export session is nil."
        case .addVideoTrack:
            return "Add video mutable track is nil."
        case .exportAsynchronously(let status):
            return "Export asynchronously other is \(status)."
        case .exportCancelled:
            return "Cancelled export video."
        case .unsupportedFileType:
            return "The output video format unsupported file type."
        }
    }
    
    /// Depending on error type, returns an underlying `Error`.
    var underlyingError: Swift.Error? {
        switch self {
        case .unknown:
            return nil
        case .error(let error):
            return error
        case .videoTrackEmpty:
            return nil
        case .addVideoTrack:
            return nil
        case .exportSessionEmpty:
            return nil
        case .exportAsynchronously:
            return nil
        case .exportCancelled:
            return nil
        case .unsupportedFileType:
            return nil
        }
    }
    
    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]
        userInfo[NSLocalizedDescriptionKey] = errorDescription
        userInfo[NSUnderlyingErrorKey] = underlyingError
        return userInfo
    }
    
    static func toError(_ error: Error?) -> Exporter.Error {
        guard let error = error else {
            return .unknown
        }
        if let error = error as? Exporter.Error {
            return error
        } else {
            return .error(error)
        }
    }
}
