# Kakapos

<img width=230px src="https://raw.githubusercontent.com/yangKJ/Kakapos/master/Screenshot/1.png" />

[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Kakapos.svg?style=flat&label=Kakapos&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Kakapos)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbeth.svg?style=flat&label=Harbeth&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Harbeth) 
![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)

---

## 📖 Overview

**Kakapos** is a media orchestration engine for Apple platforms. It organizes local assets, player frames, camera frames, images, recordings, and timeline clips into a predictable media pipeline, then passes each frame through pluggable `FrameProcessor` objects.

To keep adoption lightweight, the public surface is grouped into four small boards: **Export**, **Preview**, **Record**, and **Timeline**. `KakaposSurface` is the primary public entry layer for all four boards.

Kakapos is not a filter-kernel library. It owns media lifecycle, frame sourcing, preview routing, recording, offline export, and timeline composition. When paired with [Harbeth](https://github.com/yangKJ/Harbeth), Kakapos handles the media engine layer while Harbeth handles high-quality GPU rendering for each frame.

At the top level, Kakapos can also be understood as three public engines over one shared core: **Video Engine**, **Camera Engine**, and **Timeline Engine**. `Media Core` provides the shared frame, processor, source, sink, and pipeline contracts.

### ✨ Key Features

- **Processor-neutral frame pipeline**: Connect any processor that can transform `CVPixelBuffer`, `CMSampleBuffer`, or `MTLTexture` through `FrameProcessor`.
- **Pluggable render integration**: Keep rendering frameworks in the app layer and inject them through `FrameProcessor`; the example app demonstrates a Harbeth adapter.
- **Media sources**: Build pipelines from assets, player frames, camera frames, and image-backed timeline layers.
- **Media sinks**: Route processed frames to preview callbacks, recorders, offline exporters, or custom pixel-buffer consumers.
- **Export instruction layer**: `VideoX`, `Provider`, `Instruction`, `FilterInstruction`, `RotateInstruction`, and `WatermarkInstruction` are part of the Export board.
- **Timeline foundation**: Compose clip, image, audio, effect, group, transition, and keyframe-driven media models.

### Public Engines

Kakapos keeps a small board surface for day-to-day use, while the engine view explains the larger responsibility boundaries.

- **Video Engine**: asset input, player-frame preview, offline export, reader/writer export, and export instructions.
- **Camera Engine**: realtime camera capture, processed preview, device control, multi-segment recording, advanced outputs, and session lifecycle.
- **Timeline Engine**: timeline layers, groups, keyframes, transitions, audio mix, and timeline export.
- **Media Core**: shared `MediaFrame`, `FrameMetadata`, `FrameProcessor`, `MediaSource`, `MediaSink`, and `MediaPipeline` contracts.

### Platform Availability

| Distribution | Declared minimums | Notes |
| --- | --- | --- |
| Swift Package Manager | iOS 13, tvOS 12, watchOS 5, macOS 12 | Media Core, Video, and Timeline are the portable engine layers. Platform SDK availability still determines which AVFoundation features can run. |
| CocoaPods | iOS 13, macOS 12 | The podspec does not currently declare tvOS or watchOS deployment targets. |
| Camera capture | iOS / iPadOS | Camera hardware, microphone, permissions, depth, portrait matte, multicam, and AR capabilities are runtime-gated. |

Build success is not a substitute for device validation. Camera permissions, interruption recovery, orientation, HDR, audio/video sync, and long-recording memory behavior should be verified on the target devices.

### Lightweight Boards

Kakapos stays easier to adopt when the public surface is used in four small boards instead of one large API surface.
`KakaposSurface` is the recommended starting point for new code.
For code that only needs the recommended startup path, `KakaposSurface.starterBoards` gives the four boards in order.

Start with the smallest entry points:

- **Export**: `VideoX`, `ReaderWriterExportJob`
- **Preview**: `PreviewPipeline`, `PlayerFrameSource`, `PreviewSink`
- **Record**: `CameraEngine`, `RecordingPipeline`, `CameraSource`
- **Timeline**: `TimelinePipeline`, `TimelineComposition`

Recorded clips are also first-class bridge inputs. After camera recording finishes, `RecordedClip` can be sent back into preview, timeline, and export without rebuilding the media wiring by hand.

The fuller surface stays available behind each board:

- **Export**: `VideoX`, `Provider`, `Instruction`, `FilterInstruction`, `RotateInstruction`, `WatermarkInstruction`, `ReaderWriterExportJob`
- **Preview**: `PlayerFrameSource`, `PreviewSink`, `MediaPipeline`, `MediaProcessorChain`
- **Record**: `CameraEngine`, `RecordingPipeline`, `CameraSource`, `CameraDeviceController`, `CameraPreviewController`, `CameraRecordingController`, `RecorderSink`, `RecordingSession`, `CameraAdvancedOutput`
- **Timeline**: `TimelineComposition`, `ClipLayer`, `ImageLayer`, `AudioLayer`, `EffectLayer`, `GroupLayer`, `Transition`, `KeyframeAnimation`

You can inspect the board catalog directly in code through `KakaposCapabilityCatalog.boards` when you want a compact view of the surface and its starter types.
`KakaposCapabilityCatalog.starterBoards` and `KakaposSurface.starterBoards` expose the same ordered starter path when you want the narrowest read-only entry list.

The board entry points above are the recommended path for new code.

### Camera Engine Highlights

- `CameraEngine`: top-level camera orchestration entry that assembles source, preview, recording, and processor routing.
- `CameraEngine` is the lifecycle owner when processed preview and recording share one `CameraSource`; both branches receive frames without competing to start or stop the capture session.
- `CameraSource`: video, audio, photo, metadata-object, depth, and portrait-matte capture output.
- `CameraDeviceController`: focus, exposure, white balance, zoom, torch, flash, frame-rate, and format control.
- `CameraPreviewController`: raw preview-layer mode and processed preview mode through `FrameProcessor`.
- `CameraRecordingController`: recorder orchestration over `RecorderSink` and `RecordingSession`.
- `CameraAdvancedOutput`: metadata, depth, portrait matte, AR frame, and multicam event fan-out.

### 🔧 How It Works

Kakapos uses a `source -> processor chain -> sink` model:

```swift
let source = PlayerFrameSource(player: player)
let processor = MyFrameProcessor()
let sink = PixelBufferSink { frame in
    // Preview, inspect, record, or forward the processed frame.
}

let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
pipeline.start()
```

`MediaPipeline` keeps lossless/unbounded delivery as the default for offline work. Real-time callers can opt into an explicit bounded policy:

```swift
let previewPipeline = MediaPipeline(
    source: source,
    processors: [processor],
    sinks: [previewSink],
    deliveryPolicy: .latestOnly
)

let recordingPipeline = MediaPipeline(
    source: source,
    processors: [processor],
    sinks: [recorderSink],
    deliveryPolicy: .boundedDropNewest(maximumInFlightFrames: 6)
)
```

`PreviewPipeline` uses latest-only delivery, while `RecordingPipeline` uses a bounded real-time queue. `droppedSourceFrameCount` exposes pressure without changing offline pipelines into lossy pipelines.

A `MediaPipeline` instance is single-run. It can pause and resume while running, but `finished`, `cancelled`, and `failed` are terminal states. Create a new pipeline, processor chain, and sinks for a new run; a restartable source does not make the whole pipeline reusable.

`CameraSource` also applies bounded drop-newest admission before it creates any asynchronous frame delivery. The default ingress capacity is 6 frames, configurable through `CameraSourceConfiguration.maximumInFlightFrameCount`. Inspect `frameIngressSnapshot` for the current/high-water count and separate dropped video/audio totals.

For reusable real-time routing, build a chain once and attach it anywhere a `MediaSink` is accepted:

```swift
let previewChain = MediaProcessorChain(
    processors: [MyFrameProcessor()],
    sinks: [
        PreviewSink { image, metadata in
            // update UI
        },
        RecorderSink(outputURL: outputURL)
    ]
)
```

For offline export users, the recommended public path still starts at `KakaposSurface`:

Reader/writer export accepts an optional `videoFrameProcessingTimeout` watchdog. `performanceSnapshot` reports library-side sample, processor, backpressure, finishing, and terminal timing, and freezes at terminal completion. These metrics do not measure GPU execution, process memory peaks, or device-level HDR behavior.

---

### Export Instructions

- Create the video exporter provider.

```
let exporter = KakaposSurface.export(provider: .init(with: inputURL))

Or

let exporter = KakaposSurface.export(provider: .init(with: ``AVAsset``))
```

- Create a filter instruction and inject an app-owned renderer.

```
let processor = MyFrameProcessor()
let filtering = FilterInstruction(processor: processor)
```

`MyFrameProcessor` is owned by the consuming app and can wrap Harbeth, Metal, Core Image, or another renderer. The example app includes `HarbethExampleFrameProcessor` as a reference integration; Kakapos Core does not import Harbeth.

Recorded output can be promoted into downstream boards directly:

```swift
cameraEngine.stopRecording { result in
    guard case .success(let clip) = result else { return }

    let preview = clip.makePreviewPipeline { image, metadata in
        // inspect the recorded result
    }

    let exportTask = clip.makeExportTask(outputURL: outputURL)
    preview?.start()
    exportTask?.start { _ in }
}
```

The example app mirrors the same flow in the `Record` tab. After a capture finishes, the recorded clip can be sent back into:

- `KakaposSurface.preview(recordedClip:)`
- `KakaposSurface.timeline(recordedClip:)`
- `KakaposSurface.timelineExportTask(recordedClip:outputURL:)`

Or bridge the new processor API into the old instruction API:

```swift
let processor = MyFrameProcessor()
let filtering = FilterInstruction(processor: processor)
```

- Create a watermark instruction.

```
let textWatermark = WatermarkInstruction(
    type: .text("Kakapos", font: .boldSystemFont(ofSize: 120), color: .red),
    position: .bottomRight,
    margin: 20,
    opacity: 0.8,
)
```

The native watermark processor has an explicit SDR contract: it rejects HLG/PQ input, renders to BGRA sRGB, and publishes matching Rec.709 primaries with an sRGB transfer function. Reader/writer export returns rendering failures. The legacy video-composition callback falls back to the source frame because its API has no error channel; configure `renderingFailureHandler` before export to observe that compatibility fallback on the rendering queue.

- Create a rotate instruction.

```
let rotateInstruction = RotateInstruction(rotationAngle: selectedRotation)
```

- Convert video and then convert buffer.

```
let exporter = KakaposSurface.export(provider: provider)

/// Export the video.
/// - Parameters:
///   - options: Setup other parameters about export video.
///   - instructions: Operation procedure.
///   - complete: The conversion is complete, including success or failure.
exporter.export(options: [
    .OptimizeForNetworkUse: true,
    .ExportSessionTimeRange: TimeRangeType.range(5...28.0),
], instructions: [filtering, textWatermark, rotateInstruction], complete: { res in
    // do somthing..
}, progress: { pro in
    // progressing..
})
```

### Custom Instruction

You can create your own custom instructions by following these steps:

1. **Create a calss that conforms to the `InstructionProtocol` & `Instruction`**
2. **Use your custom instruction**


### Example: Create a Brightness Adjustment Instruction

```swift
public class BrightnessInstruction: CompositionInstruction {
    public let timeRange: CMTimeRange
    public let brightness: Float
    
    public init(brightness: Float, timeRange: CMTimeRange = .init(start: .zero, duration: .positiveInfinity)) {
        self.brightness = brightness
        self.timeRange = timeRange
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func operationPixelBuffer(_ buffer: CVPixelBuffer, block: @escaping BufferBlock, for request: AVAsynchronousVideoCompositionRequest) {
        if let brightnessBuffer = processBrightness(buffer) {
            block(brightnessBuffer) 
        }
    }
    
    func processBrightness(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Implement brightness adjustment logic
        // This could use CoreImage, Harbeth, or other frameworks
        return pixelBuffer
    }
}
```

By following this pattern, you can create any custom video processing instructions you need.
 
Custom instructions remain useful for export-only workflows. For new media engine work, prefer `FrameProcessor`, `MediaSource`, `MediaSink`, and `MediaPipeline`.

### Timeline Foundation

```swift
let timeline = TimelineComposition(renderSize: CGSize(width: 720, height: 1280))
timeline.addLayer(ClipLayer(asset: firstAsset, timeRange: CMTimeRange(start: .zero, duration: firstDuration)))
timeline.addLayer(ClipLayer(asset: secondAsset, timeRange: CMTimeRange(start: firstDuration, duration: secondDuration)))

let compiled = timeline.compile()
guard compiled.isValid else {
    print(compiled.diagnostics)
    return
}
let item = AVPlayerItem(asset: compiled.composition)
item.videoComposition = compiled.videoComposition
item.audioMix = compiled.audioMix
```

Track insertion failures are retained in `CompiledTimelineComposition.diagnostics`. Export jobs created from an invalid compiled timeline fail closed instead of silently exporting a partial composition.

### Commercial Boundary

The open-source Kakapos package provides the media engine foundation: processor-neutral frame routing, offline export compatibility, processor integration contracts, player frame sourcing, recording primitives, and timeline models.

Private Kakapos Pro / Visual Engine work can extend this base with production camera UX, template systems, advanced timeline effects, performance tuning, private processor adapters, and complete starter kits.

### CocoaPods

- If you want to import [**media engine**](https://github.com/yangKJ/Kakapos) module, you need in your Podfile:

```
pod 'Kakapos'
```

- If you want to import [**render engine**](https://github.com/yangKJ/Harbeth) module, you need in your Podfile:

```
pod 'Harbeth'
```

Harbeth is optional. The consuming app owns the adapter that conforms Harbeth or another renderer to Kakapos `FrameProcessor`.

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Kakapos requires the Xcode 16+ / Swift 6 toolchain and currently compiles in Swift 5 language mode while its concurrency contracts are migrated. The library supports iOS 13+, while the example app currently targets iOS 16.6.

To integrate Kakapos into your Xcode project using Swift Package Manager, add it to the dependencies value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yangKJ/Kakapos.git", from: "1.1.0"),
]
```

Link only the products your app owns:

- `KakaposMediaCore`: frame, processor, source, sink, and pipeline contracts.
- `KakaposVideo`: processed preview, asset sources, transcode, export, and artifact validation.
- `KakaposTimeline`: composition, keyframes, transitions, and timeline export.
- `KakaposCamera`: capture, processed camera preview, and recording. Camera produces `RecordedClip`; downstream Video or Timeline modules consume it.
- `Kakapos`: umbrella product for demos or apps that intentionally need every engine.

For example, an app that only rescues existing videos should link and import `KakaposMediaCore` plus `KakaposVideo`; it should not pull in Camera or Timeline.

### Migration Note

The next distribution baseline raises the library minimum from iOS 12 to iOS 13 and removes the conditional Core-owned `HarbethFrameProcessor` and `.kaka.filtering` APIs. Move that bridge into the consuming app (the example app provides `HarbethExampleFrameProcessor`) and inject it through `FrameProcessor`. Treat this as a breaking distribution change when choosing the next release version.

### Remarks

> The general process is almost like this, the Demo is also written in great detail, you can check it out for yourself.🎷
>
> [**KakaposDemo**](https://github.com/yangKJ/Kakapos)
>
> Tip: If you find it helpful, please help me with a star. If you have any questions or needs, you can also issue.
>
> Thanks.🎇

### About the author
- 🎷 **E-mail address: [yangkj310@gmail.com](yangkj310@gmail.com) 🎷**
- 🎸 **GitHub address: [yangKJ](https://github.com/yangKJ) 🎸**

Buy me a coffee or support me on [GitHub](https://github.com/sponsors/yangKJ?frequency=one-time&sponsor=yangKJ).

<a href="https://www.buymeacoffee.com/yangkj3102">
<img width=25% alt="yellow-button" src="https://user-images.githubusercontent.com/1888355/146226808-eb2e9ee0-c6bd-44a2-a330-3bbc8a6244cf.png">
</a>

Alipay or WeChat. Thanks.

<p align="left">
<img src="https://raw.githubusercontent.com/yangKJ/Harbeth/master/Screenshot/WechatIMG1.jpg" width=30% hspace="1px">
<img src="https://raw.githubusercontent.com/yangKJ/Harbeth/master/Screenshot/WechatIMG2.jpg" width=30% hspace="15px">
</p>

-----

### License
Kakapos is available under the [MIT](LICENSE) license. See the [LICENSE](LICENSE) file for more info.

-----
