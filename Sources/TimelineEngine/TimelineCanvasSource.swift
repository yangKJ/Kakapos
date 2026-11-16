// 作者：Condy
import AVFoundation
import AudioToolbox
import Foundation

/// 为无视频区间提供有界的时钟轨；单进程复用一帧黑色视频，不预生成整段影片。
final class TimelineCanvasSource: @unchecked Sendable {
    private let url: URL
    let asset: AVURLAsset
    static let shared: Result<TimelineCanvasSource, Error> = Result { try TimelineCanvasSource() }

    private init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("kakapos-canvas-\(UUID().uuidString).mov")
        asset = AVURLAsset(url: url)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
            writer.add(input)
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard writer.canAdd(audio) else { throw CocoaError(.fileWriteUnknown) }
            writer.add(audio)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                  let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let bytes = CVPixelBufferGetBaseAddress(buffer) {
                memset(bytes, 0, CVPixelBufferGetBytesPerRow(buffer) * 16)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: .zero) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            guard audio.append(try Self.silentSample()) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            audio.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
            input.markAsFinished()
            let finished = DispatchSemaphore(value: 0)
            writer.finishWriting { finished.signal() }
            guard finished.wait(timeout: .now() + 10) == .success, writer.status == .completed else {
                writer.cancelWriting()
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    private static func silentSample() throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        var block: CMBlockBuffer?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr,
              CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 88200,
                blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 88200, flags: 0, blockBufferOut: &block) == noErr,
              let block else { throw CocoaError(.fileWriteUnknown) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: 88200)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?; var size = 2
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format,
            sampleCount: 44100, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }

    static func padAudioIfNeeded(_ composition: AVMutableComposition) throws -> AVCompositionTrack? {
        let tracks = composition.tracks(withMediaType: .audio)
        guard let end = tracks.map(\.timeRange.end).max(), end < composition.duration else { return nil }
        let source = try shared.get()
        guard let audio = source.asset.tracks(withMediaType: .audio).first,
              let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadUnknown)
        }
        let duration = composition.duration
        var cursor = end
        while cursor < duration {
            let count = min(audio.timeRange.duration, duration - cursor)
            try target.insertTimeRange(CMTimeRange(start: audio.timeRange.start, duration: count), of: audio, at: cursor)
            cursor = cursor + count
        }
        return target
    }

    static func extend(_ composition: AVMutableComposition, to duration: CMTime) throws {
        guard duration.isNumeric, duration > .zero else { return }
        let source = try shared.get()
        guard let track = source.asset.tracks(withMediaType: .video).first,
              let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadUnknown)
        }
        try target.insertTimeRange(track.timeRange, of: track, at: .zero)
        target.scaleTimeRange(track.timeRange, toDuration: duration)
    }
}
