# Kakapos

<img width=230px src="https://raw.githubusercontent.com/yangKJ/Kakapos/master/Screenshot/1.png" />

[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Kakapos.svg?style=flat&label=Kakapos&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Kakapos)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbeth.svg?style=flat&label=Harbeth&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Harbeth) 
![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)

---

## 📖 Overview

**Kakapos** is a media orchestration engine for Apple platforms. It organizes local assets, player frames, camera frames, images, recordings, and timeline clips into a predictable media pipeline, then passes each frame through pluggable `FrameProcessor` objects.

Kakapos is not a filter-kernel library. It owns media lifecycle, frame sourcing, preview routing, recording, offline export, and timeline composition. When paired with [Harbeth](https://github.com/yangKJ/Harbeth), Kakapos handles the media engine layer while Harbeth handles high-quality GPU rendering for each frame.

### ✨ Key Features

- **Processor-neutral frame pipeline**: Connect any processor that can transform `CVPixelBuffer`, `CMSampleBuffer`, or `MTLTexture` through `FrameProcessor`.
- **Harbeth integration**: Use `HarbethFrameProcessor` when you want the official Kakapos + Harbeth render path.
- **Media sources**: Build pipelines from assets, player frames, camera frames, and image-backed timeline layers.
- **Media sinks**: Route processed frames to preview callbacks, recorders, offline exporters, or custom pixel-buffer consumers.
- **Offline compatibility**: Existing `VideoX`, `Provider`, `Instruction`, `FilterInstruction`, `RotateInstruction`, and `WatermarkInstruction` APIs remain available.
- **Timeline foundation**: Compose clip, image, audio, effect, group, transition, and keyframe-driven media models.

### Lightweight Boards

Kakapos stays easier to adopt when the public surface is used in four small boards instead of one large API surface:

- **Export**: `VideoX`, `Provider`, `Instruction`, `FilterInstruction`, `RotateInstruction`, `WatermarkInstruction`, `ReaderWriterExportJob`
- **Preview**: `PlayerFrameSource`, `PreviewSink`, `MediaPipeline`, `MediaProcessorChain`
- **Record**: `CameraSource`, `RecorderSink`, `RecordingSession`
- **Timeline**: `TimelineComposition`, `ClipLayer`, `ImageLayer`, `AudioLayer`, `EffectLayer`, `GroupLayer`, `Transition`, `KeyframeAnimation`

You can inspect the board catalog directly in code through `KakaposCapabilityCatalog.boards` when you want a compact view of the surface.

### 🔧 How It Works

Kakapos uses a `source -> processor chain -> sink` model:

```swift
let source = PlayerFrameSource(player: player)
let processor = HarbethFrameProcessor(filters: filters)
let sink = PixelBufferSink { frame in
    // Preview, inspect, record, or forward the processed frame.
}

let pipeline = MediaPipeline(source: source, processors: [processor], sinks: [sink])
pipeline.start()
```

For reusable real-time routing, build a chain once and attach it anywhere a `MediaSink` is accepted:

```swift
let previewChain = MediaProcessorChain(
    processors: [HarbethFrameProcessor(filters: filters)],
    sinks: [
        PreviewSink { image, metadata in
            // update UI
        },
        RecorderSink(outputURL: outputURL)
    ]
)
```

For existing offline export users, the instruction-based API still works:

---

### VideoX Compatibility

- Create the video exporter provider.

```
let exporter = VideoX.init(provider: .init(with: ``URL Link``))

Or

let exporter = VideoX.init(provider: .init(with: ``AVAsset``))
```

- Create filter instruction and add Harbeth filters.

```
let filters1: [C7FilterProtocol] = [
    C7LookupTable(name: "lut_abao"),
    C7SplitScreen(type: .two),
    C7Mirror(),
    C7Contrast(contrast: 0.9),
    C7SoulOut(soul: 0.3),
]
let filters2: [C7FilterProtocol] = [
    C7Flip(horizontal: true, vertical: true),
    C7SoulOut(soul: 0.3),
]

let filtering = FilterInstruction { buffer, time, callback in
    if time >= 0, time < 3 {
        buffer.kaka.filtering(with: filters1, callback: callback)
    } else {
        let dest = HarbethIO(element: buffer, filters: filters2)
        dest.transmitOutput(success: callback)
    }
}
```

Or bridge the new processor API into the old instruction API:

```swift
let processor = HarbethFrameProcessor(filters: [C7LookupTable(name: "lut_abao")])
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

- Create a rotate instruction.

```
let rotateInstruction = RotateInstruction(rotationAngle: selectedRotation)
```

- Convert video and then convert buffer.

```
let exporter = VideoX.init(provider: provider)

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
let item = AVPlayerItem(asset: compiled.composition)
item.videoComposition = compiled.videoComposition
item.audioMix = compiled.audioMix
```

### Commercial Boundary

The open-source Kakapos package provides the media engine foundation: processor-neutral frame routing, offline export compatibility, Harbeth wiring, player frame sourcing, recording primitives, and timeline models.

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

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Xcode 11+ is required to build [Kakapos](https://github.com/yangKJ/Kakapos) using Swift Package Manager.

To integrate Kakapos into your Xcode project using Swift Package Manager, add it to the dependencies value of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yangKJ/Kakapos.git", branch: "master"),
]
```

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
