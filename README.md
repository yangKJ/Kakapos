# Kakapos

[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Kakapos.svg?style=flat&label=Kakapos&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Kakapos) 
![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)

[**Kakapos**](https://github.com/yangKJ/Kakapos) is a video add filter tool that supports network and local urls, as well as album videos.

High-performance and flexible video editing and exporting framework.

Add filter with [CoreImage](https://developer.apple.com/documentation/coreimage)/[Harbeth](https://github.com/yangKJ/Harbth)/[GPUImage](https://github.com/BradLarson/GPUImage)/[MetalPetal](https://github.com/MetalPetal/MetalPetal)/[BBMetalImage](https://github.com/Silence-GitHub/BBMetalImage) and so on.

-------

### Used

- Create the video exporter provider.

```
let provider = VideoX.Provider.init(with: ``URL Link``)

Or

let provider = VideoX.Provider.init(with: ``AVAsset``)
```

- Create filter instruction and add filters.

```
let filters: [C7FilterProtocol] = [
    C7LookupTable(name: "lut_abao"),
    C7SplitScreen(type: .two),
]
let filters2: [C7FilterProtocol] = [
    C7Flip(horizontal: true, vertical: true),
    C7SoulOut(soul: 0.3),
]

let filtering = FilterInstruction { buffer, time, callback in
    if time >= 0, time < 10 {
        let dest = BoxxIO(element: buffer, filters: filters)
        dest.transmitOutput(success: callback)
    } else {
        let dest = BoxxIO(element: buffer, filters: filters2)
        dest.transmitOutput(success: callback)
    }
}
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
], instructions: [filtering], complete: { res in
    // do somthing..
}, progress: { pro in
    // progressing..
})
```

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
