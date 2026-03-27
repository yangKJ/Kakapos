# Kakapos

<img width=230px src="https://raw.githubusercontent.com/yangKJ/Kakapos/master/Screenshot/1.png" />

[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Kakapos.svg?style=flat&label=Kakapos&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Kakapos)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbeth.svg?style=flat&label=Harbeth&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Harbeth) 
![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)

---

## 📖 Overview

**Kakapos** is a high-performance, flexible video editing and exporting framework designed for iOS, macOS, watchOS, and tvOS. It provides a powerful set of tools for adding filters, watermarks, rotations, and other effects to videos from various sources including network URLs, local files, and album videos.

### ✨ Key Features

- **Multi-source Support**: Process videos from network URLs, local files, and album assets
- **Filter Integration**: Compatible with multiple filter frameworks:
  - [CoreImage](https://developer.apple.com/documentation/coreimage)
  - [Harbeth](https://github.com/yangKJ/Harbeth) (Metal-based filter framework)
  - [GPUImage](https://github.com/BradLarson/GPUImage)
  - [MetalPetal](https://github.com/MetalPetal/MetalPetal)
  - [BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage)
  - Any custom filter framework that converts CVPixelBuffer
- **Comprehensive Instructions**: Built-in support for:
  - Filter application with time-based control
  - Text and image watermarks with customizable positioning
  - Video rotation (90°, 180°, 270°)
  - Custom instruction creation for extended functionality
- **High Performance**: Optimized for speed and efficiency using Metal where available
- **Flexible Export Options**: Customizable export settings including time range, quality, and network optimization

### 🎯 Why Choose Kakapos?

- **Easy to Use**: Simple API with clear instruction-based architecture
- **Extensible**: Create custom instructions for your specific video processing needs
- **Performance Focused**: Leverages hardware acceleration for fast processing
- **Versatile**: Supports a wide range of video sources and filter frameworks
- **Well Documented**: Comprehensive documentation and example code

### 🔧 How It Works

Kakapos uses an instruction-based architecture where you define a series of processing steps (instructions) that are applied to each video frame. These instructions are processed in sequence, allowing for complex video transformations with minimal code.

The framework handles the heavy lifting of video frame processing, leaving you free to focus on creating the desired visual effects.

---

### Used

- Create the video exporter provider.

```
let exporter = VideoX.init(provider: .init(with: ``URL Link``))

Or

let exporter = VideoX.init(provider: .init(with: ``AVAsset``))
```

- Create filter instruction and add filters.

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
 
Such as:
- Color adjustment instructions
- Special effects instructions
- Text overlay instructions
- Audio processing instructions
- And more!

### CocoaPods

- If you want to import [**video exporter**](https://github.com/yangKJ/Kakapos) module, you need in your Podfile: 

```
pod 'Kakapos'
```

- If you want to import [**metal filter**](https://github.com/yangKJ/Harbeth) module, you need in your Podfile: 

```
pod 'Harbeth'
```

### Swift Package Manager

[Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies.

> Xcode 11+ is required to build [Kakapos](https://github.com/yangKJ/Kakapos) using Swift Package Manager.

To integrate Harbeth into your Xcode project using Swift Package Manager, add it to the dependencies value of your `Package.swift`:

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
Harbeth is available under the [MIT](LICENSE) license. See the [LICENSE](LICENSE) file for more info.

-----
