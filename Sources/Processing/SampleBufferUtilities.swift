//
//  SampleBufferUtilities.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import CoreVideo

public enum SampleBufferUtilities {
    public static func replacingImageBuffer(of sampleBuffer: CMSampleBuffer, with imageBuffer: CVImageBuffer) -> CMSampleBuffer? {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return nil
        }
        var timingInfo = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == noErr else {
            return nil
        }
        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescriptionOut: &formatDescription) == noErr,
              let description = formatDescription else {
            return nil
        }
        var output: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescription: description,
            sampleTiming: &timingInfo,
            sampleBufferOut: &output
        )
        return output
    }
}
