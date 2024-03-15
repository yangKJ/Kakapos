//
//  AVSourciable.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/10.
//

import Foundation
import AVFoundation

public protocol AVSourciable {
    associatedtype Element
    
    var element: Element { get }
    
    init(element: Element)
    
    var duration: CMTime { get set }
    
    var isLoaded: Bool { get set }
    
    func load(completion: @escaping (Result<Element, Exporter.Error>) -> Void)
    
    func tracks(for type: AVMediaType) -> [AVAssetTrack]
}
