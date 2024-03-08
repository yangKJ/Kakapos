//
//  MovieFileType.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import Foundation
import AVFoundation

enum MovieFileType {
    /// MOV是苹果设计的一种流行的视频文件格式。 它旨在支持QuickTime播放器。 MOV文件包含视频，音频，字幕，时间码和其他媒体类型。
    /// 由于它是一种非常高质量的视频格式，因此MOV文件在计算机上会占用更多的存储空间。
    case mov
    /// MPEG-4 Part 14或MP4是2001年推出的最早的数字视频文件格式之一。大多数数字平台和设备都支持MP4。
    /// MP4格式可以存储音频文件，视频文件，静止图像和文本。 此外，MP4提供高质量的视频，同时保持相对较小的文件大小。
    case mp4
    
    case m4a
    
    case mobile3gp
}

extension MovieFileType {
    var avFileType: AVFileType {
        switch self {
        case .mov:
            return .mov
        case .mp4:
            return .mp4
        case .m4a:
            return .m4a
        case .mobile3gp:
            return .mobile3GPP
        }
    }
    
    static func from(url: URL) -> MovieFileType? {
        switch url.pathExtension.lowercased() {
        case "mp4":
            return MovieFileType.mp4
        case "mov", "qt":
            return MovieFileType.mov
        case "m4a":
            return MovieFileType.m4a
        case "3gp", "3gpp", "sdv":
            return MovieFileType.mobile3gp
        default:
            return nil
        }
    }
}
