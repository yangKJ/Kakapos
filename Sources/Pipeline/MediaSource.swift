//
//  MediaSource.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation

public protocol MediaSourceDelegate: AnyObject {
    func mediaSource(_ source: MediaSource, didOutput frame: MediaFrame)
    func mediaSource(_ source: MediaSource, didFail error: Error)
    func mediaSourceDidFinish(_ source: MediaSource)
}

public extension MediaSourceDelegate {
    func mediaSource(_ source: MediaSource, didFail error: Error) {}
    func mediaSourceDidFinish(_ source: MediaSource) {}
}

public protocol MediaSource: AnyObject {
    var delegate: MediaSourceDelegate? { get set }
    func start()
    func pause()
    func resume()
    func stop()
    func cancel()
}
