#if canImport(UIKit) && !os(watchOS)
//
//  KakaposRealtimeProtocols.swift
//  KakaposRealtime (Kakapos)
//
//  Copyright (c) 2016-present patrick piemonte (http://patrickpiemonte.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import AVFoundation
import CoreVideo
#if USE_ARKIT
import ARKit
#endif

// MARK: - KakaposRealtimeDelegate Dictionary Keys

/// Delegate callback dictionary key for photo metadata
public let KakaposRealtimePhotoMetadataKey = "KakaposRealtimePhotoMetadataKey"

/// Delegate callback dictionary key for JPEG data
public let KakaposRealtimePhotoJPEGKey = "KakaposRealtimePhotoJPEGKey"

/// Delegate callback dictionary key for cropped JPEG data
public let KakaposRealtimePhotoCroppedJPEGKey = "KakaposRealtimePhotoCroppedJPEGKey"

/// Delegate callback dictionary key for raw image data
public let KakaposRealtimePhotoRawImageKey = "KakaposRealtimePhotoRawImageKey"

/// Delegate callback dictionary key for a photo thumbnail
public let KakaposRealtimePhotoThumbnailKey = "KakaposRealtimePhotoThumbnailKey"

/// Delegate callback dictionary key for file data, configure using KakaposRealtimePhotoConfiguration.outputFileDataFormat
public let KakaposRealtimePhotoFileDataKey = "KakaposRealtimePhotoFileDataKey"

// MARK: - KakaposRealtimeDelegate

/// KakaposRealtime delegate, provides updates for authorization, configuration changes, session state, preview state, and mode changes.
public protocol KakaposRealtimeDelegate: AnyObject {

    // configuration
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoConfiguration videoConfiguration: KakaposRealtimeVideoConfiguration)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateAudioConfiguration audioConfiguration: KakaposRealtimeAudioConfiguration)

    // session
    func kakaposRealtimeSessionWillStart(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeSessionDidStart(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeSessionDidStop(_ kakaposRealtime: KakaposRealtime)

    // session interruption
    func kakaposRealtimeSessionWasInterrupted(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeSessionInterruptionEnded(_ kakaposRealtime: KakaposRealtime)

    // mode
    func kakaposRealtimeCaptureModeWillChange(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeCaptureModeDidChange(_ kakaposRealtime: KakaposRealtime)

}

/// Preview delegate, provides update for
public protocol KakaposRealtimePreviewDelegate: AnyObject {

    // preview
    func kakaposRealtimeWillStartPreview(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDidStopPreview(_ kakaposRealtime: KakaposRealtime)

}

/// Device delegate, provides updates on device position, orientation, clean aperture, focus, exposure, and white balances changes.
public protocol KakaposRealtimeDeviceDelegate: AnyObject {

    // position, orientation
	var kakaposRealtimeCurrentDeviceOrientation: (() -> AVCaptureVideoOrientation)? { get }
    func kakaposRealtimeDevicePositionWillChange(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDevicePositionDidChange(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDeviceOrientationWillChange(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeDeviceOrientation deviceOrientation: KakaposRealtimeDeviceOrientation)

    // format
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeDeviceFormat deviceFormat: AVCaptureDevice.Format)

    // aperture, lens
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeCleanAperture cleanAperture: CGRect)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeLensPosition lensPosition: Float)

    // focus, exposure, white balance
    func kakaposRealtimeWillStartFocus(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDidStopFocus(_  kakaposRealtime: KakaposRealtime)

    func kakaposRealtimeWillChangeExposure(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDidChangeExposure(_ kakaposRealtime: KakaposRealtime)
	func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeExposureDuration exposureDuration: CMTime)

    func kakaposRealtimeWillChangeWhiteBalance(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDidChangeWhiteBalance(_ kakaposRealtime: KakaposRealtime)

}

public extension KakaposRealtimeDeviceDelegate {

	// Empty default implementations of recently added protocol methods, to make them optional and not break existing code.

	var kakaposRealtimeCurrentDeviceOrientation: (() -> AVCaptureVideoOrientation)? { nil }
    func kakaposRealtimeDeviceOrientationWillChange(_ kakaposRealtime: KakaposRealtime) { }

	func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didChangeExposureDuration exposureDuration: CMTime) {
	}
}

// MARK: - KakaposRealtimeFlashAndTorchDelegate

/// Flash and torch delegate, provides updates on active flash and torch related changes.
public protocol KakaposRealtimeFlashAndTorchDelegate: AnyObject {

    func kakaposRealtimeDidChangeFlashMode(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeDidChangeTorchMode(_ kakaposRealtime: KakaposRealtime)

    func kakaposRealtimeFlashActiveChanged(_ kakaposRealtime: KakaposRealtime)
    func kakaposRealtimeTorchActiveChanged(_ kakaposRealtime: KakaposRealtime)

    func kakaposRealtimeFlashAndTorchAvailabilityChanged(_ kakaposRealtime: KakaposRealtime)

}

// MARK: - KakaposRealtimeVideoDelegate

/// Video delegate, provides updates on video related recording and capture functionality.
/// All methods are called on the main queue with the exception of kakaposRealtime:renderToCustomContextWithSampleBuffer:onQueue.
public protocol KakaposRealtimeVideoDelegate: AnyObject {

    // video zoom
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didUpdateVideoZoomFactor videoZoomFactor: Float)

    // video processing
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessRawVideoSampleBuffer sampleBuffer: CMSampleBuffer, onQueue queue: DispatchQueue)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue)

    // ARKit video processing
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, willProcessFrame frame: AnyObject, timestamp: TimeInterval, onQueue queue: DispatchQueue)

    // video recording session
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupVideoInSession session: KakaposRealtimeSession)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSetupAudioInSession session: KakaposRealtimeSession)

    // clip start/stop
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didStartClipInSession session: KakaposRealtimeSession)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteClip clip: KakaposRealtimeClip, inSession session: KakaposRealtimeSession)

    // clip file I/O
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession)

    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: KakaposRealtimeSession)

    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didSkipAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: KakaposRealtimeSession)

    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompleteSession session: KakaposRealtimeSession)

    // video frame photo
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didCompletePhotoCaptureFromVideoFrame photoDict: [String: Any]?)

}

// MARK: - KakaposRealtimePhotoDelegate

/// Photo delegate, provides updates on photo related capture functionality.
public protocol KakaposRealtimePhotoDelegate: AnyObject {
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration)
    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: KakaposRealtimePhotoConfiguration)

    func kakaposRealtime(_ kakaposRealtime: KakaposRealtime, didFinishProcessingPhoto photo: AVCapturePhoto, photoDict: [String: Any], photoConfiguration: KakaposRealtimePhotoConfiguration)

    func kakaposRealtimeDidCompletePhotoCapture(_ kakaposRealtime: KakaposRealtime)
}

// MARK: - KakaposRealtimeDepthDataDelegate

#if USE_TRUE_DEPTH
/// Depth data delegate, provides depth data updates
public protocol KakaposRealtimeDepthDataDelegate: AnyObject {
    func depthDataOutput(_ kakaposRealtime: KakaposRealtime, didOutput depthData: AVDepthData, timestamp: CMTime)
    func depthDataOutput(_ kakaposRealtime: KakaposRealtime, didDrop depthData: AVDepthData, timestamp: CMTime, reason: AVCaptureOutput.DataDroppedReason)
}
#endif

// MARK: - KakaposRealtimePortraitEffectsMatteDelegate

/// Portrait Effects Matte delegate, provides portrait effects matte updates
public protocol KakaposRealtimePortraitEffectsMatteDelegate: AnyObject {
    func portraitEffectsMatteOutput(_ kakaposRealtime: KakaposRealtime, didOutput portraitEffectsMatte: AVPortraitEffectsMatte)
}

// MARK: - KakaposRealtimeMetadataOutputObjectsDelegate

/// Metadata Output delegate, provides objects like faces and barcodes
public protocol KakaposRealtimeMetadataOutputObjectsDelegate: AnyObject {
    func metadataOutputObjects(_ kakaposRealtime: KakaposRealtime, didOutput metadataObjects: [AVMetadataObject])
}

#endif
