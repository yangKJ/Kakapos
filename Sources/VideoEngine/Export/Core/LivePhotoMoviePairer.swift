//
//  LivePhotoMoviePairer.swift
//  KakaposVideo
//
//  Created by Condy on 2026/10/6.
//

import AVFoundation
import Foundation

/// 对已渲染的 MOV 做压缩包重封装，保留声音并写入原生 Live Photo 元数据。
@available(iOS 16, macOS 13, tvOS 16, *)
public enum LivePhotoMoviePairer {
    public enum PairError: Error { case invalidResource, incompatibleWriter, appendFailed, missingPairMetadata }

    public struct Metadata: Sendable {
        public let contentIdentifier: String
        public let keyPhotoTime: CMTime
        public let duration: CMTime
        public let hasAudio: Bool
    }

    public static func inspect(at url: URL) async throws -> Metadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let items = try await asset.load(.metadata)
        guard let item = items.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier }),
              let identifier = try await item.load(.stringValue), !identifier.isEmpty else { throw PairError.missingPairMetadata }
        let tracks = try await asset.loadTracks(withMediaType: .metadata)
        for track in tracks {
            let reader = try AVAssetReader(asset: asset)
            defer { reader.cancelReading() }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            guard reader.startReading() else { continue }
            var count = 0
            while let sample = output.copyNextSampleBuffer(), count < 256 {
                count += 1
                guard let group = AVTimedMetadataGroup(sampleBuffer: sample), group.items.contains(where: {
                    ($0.key as? String) == "com.apple.quicktime.still-image-time"
                        || $0.identifier?.rawValue.hasSuffix("com.apple.quicktime.still-image-time") == true
                }) else { continue }
                let time = group.timeRange.start
                guard time.isValid, time.isNumeric, time >= .zero, time < duration else { throw PairError.invalidResource }
                let audio = try await asset.loadTracks(withMediaType: .audio)
                return Metadata(contentIdentifier: identifier, keyPhotoTime: time, duration: duration, hasAudio: !audio.isEmpty)
            }
        }
        throw PairError.missingPairMetadata
    }

    public static func pair(inputURL: URL, outputURL: URL,
                            contentIdentifier: String, keyPhotoTime: CMTime) async throws {
        guard !contentIdentifier.isEmpty, keyPhotoTime.isValid, keyPhotoTime.isNumeric else { throw PairError.invalidResource }
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        guard keyPhotoTime >= .zero, keyPhotoTime < duration else { throw PairError.invalidResource }
        let tracks = try await asset.load(.tracks).filter { $0.mediaType == .video || $0.mediaType == .audio }
        guard tracks.contains(where: { $0.mediaType == .video }) else { throw PairError.invalidResource }
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let identifier = AVMutableMetadataItem()
        identifier.identifier = .quickTimeMetadataContentIdentifier
        identifier.value = contentIdentifier as NSString
        identifier.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identifier]
        var branches: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for track in tracks {
            let descriptions = try await track.load(.formatDescriptions)
            guard let hint = descriptions.first else { throw PairError.invalidResource }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: hint)
            if track.mediaType == .video { input.transform = try await track.load(.preferredTransform) }
            guard reader.canAdd(output), writer.canAdd(input) else { throw PairError.incompatibleWriter }
            reader.add(output); writer.add(input); branches.append((output, input))
        }
        var format: CMFormatDescription?
        let specifications: [[String: Any]] = [[
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String
        ]]
        guard CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: specifications as CFArray,
            formatDescriptionOut: &format) == noErr, let format else { throw PairError.missingPairMetadata }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else { throw PairError.incompatibleWriter }
        writer.add(metadataInput)
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? reader.error ?? PairError.appendFailed }
        var completed = false
        defer {
            if !completed {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        writer.startSession(atSourceTime: .zero)
        let stillTime = AVMutableMetadataItem()
        stillTime.key = "com.apple.quicktime.still-image-time" as NSString
        stillTime.keySpace = .quickTimeMetadata
        stillTime.value = NSNumber(value: Int8(0))
        stillTime.dataType = kCMMetadataBaseDataType_SInt8 as String
        while !metadataInput.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw writer.error ?? PairError.appendFailed }
            try await Task.sleep(for: .milliseconds(2))
        }
        guard adaptor.append(AVTimedMetadataGroup(items: [stillTime], timeRange: CMTimeRange(start: keyPhotoTime, duration: CMTime(value: 1, timescale: 30)))) else {
            throw PairError.missingPairMetadata
        }
        metadataInput.markAsFinished()
        var lastProgress = ContinuousClock.now
        var pending = branches.map { $0.0.copyNextSampleBuffer() }
        for index in branches.indices where pending[index] == nil { branches[index].1.markAsFinished() }
        while pending.contains(where: { $0 != nil }) {
            try Task.checkCancellation()
            var madeProgress = false
            for index in branches.indices {
                let (output, input) = branches[index]
                guard let sample = pending[index], input.isReadyForMoreMediaData else { continue }
                guard input.append(sample) else { throw writer.error ?? PairError.appendFailed }
                pending[index] = output.copyNextSampleBuffer()
                if pending[index] == nil { input.markAsFinished() }
                madeProgress = true
                lastProgress = .now
            }
            guard writer.status == .writing else { throw writer.error ?? PairError.appendFailed }
            guard lastProgress.duration(to: .now) < .seconds(30) else { throw PairError.appendFailed }
            if !madeProgress { try await Task.sleep(for: .milliseconds(2)) }
        }
        guard reader.status == .completed else { throw reader.error ?? PairError.appendFailed }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PairError.appendFailed }
        let result = AVURLAsset(url: outputURL)
        let metadata = try await result.load(.metadata)
        guard let recorded = metadata.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier }),
              try await recorded.load(.stringValue) == contentIdentifier,
              try await result.loadTracks(withMediaType: .metadata).isEmpty == false else { throw PairError.missingPairMetadata }
        let info = try await inspect(at: outputURL)
        guard info.contentIdentifier == contentIdentifier, abs(info.keyPhotoTime.seconds - keyPhotoTime.seconds) < 0.04 else { throw PairError.missingPairMetadata }
        completed = true
    }
}
