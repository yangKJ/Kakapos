//
//  Kakapos.swift
//  KakaposExamples
//
//  Created by Condy on 2024/3/3.
//

import Foundation
import AVFoundation

/// Add the `kaka` prefix namespace.
public struct KakaposWrapper<Base> {
    /// Stores the type or meta-type of any extended type.
    public private(set) var base: Base
    /// Create an instance from the provided value.
    public init(base: Base) {
        self.base = base
    }
}

public protocol KakaposCompatible { }

extension KakaposCompatible {
    
    public var kaka: KakaposWrapper<Self> {
        get { KakaposWrapper(base: self) }
        set { }
    }
    
    public static var kaka: KakaposWrapper<Self>.Type {
        KakaposWrapper<Self>.self
    }
}

extension AVAssetTrack: KakaposCompatible { }
extension FileManager: KakaposCompatible { }
