# Kakapos

[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Kakapos.svg?style=flat&label=Kakapos&colorA=28a745&&colorB=4E4E4E)](https://cocoapods.org/pods/Kakapos) 
![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)

[**Kakapos**](https://github.com/yangKJ/Kakapos) is a video add filter tool that supports network and local urls, as well as album videos.

Support macOS, iOS, tvOS and watchOS.

-------

### Used

- Set the conversion video storage sandbox link.

```
// Creating temp path to save the converted video
let outputURL: URL = {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let outputURL = documents.appendingPathComponent("condy_exporter_video.mp4")
    
    // Check if the file already exists then remove the previous file
    if FileManager.default.fileExists(atPath: outputURL.path) {
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            //completionHandler(nil, error)
        }
    }
    return outputURL
}()
```

- Create the video exporter instance.

```
let exporter = Exporter.init(videoURL: ``URL Link``, delegate: self)

Or

let exporter = Exporter.init(asset: ``AVAsset``, delegate: self)
```

- Implement the agreement `ExporterDelegate`.

```
/// Video export successed.
/// - Parameters:
///   - exporter: VideoExporter
///   - videoURL: Export the successful video url, Be equivalent to outputURL.
func export(_ exporter: Kakapos.Exporter, success videoURL: URL) {
    self.view.hideAllToasts()
    let player = AVPlayer(url: videoURL)
    let vc = AVPlayerViewController()
    vc.player = player
    self.present(vc, animated: true) {
        vc.player?.play()
    }
}

/// Video export failure.
/// - Parameters:
///   - exporter: VideoExporter
///   - error: Failure error message.
func export(_ exporter: Kakapos.Exporter, failed error: Kakapos.Exporter.Error) {
    // do someing..
}
```

- Convert video and add filters, convert buffer.

```
let filters: [C7FilterProtocol] = [
    C7Flip(horizontal: true, vertical: false),
    C7ColorConvert(with: .gray),
    C7SoulOut(soul: 0.3),
    MPSGaussianBlur(radius: 5),
]

/// Export the video after injecting the filter.
/// - Parameters:
///   - outputURL: Specifies the sandbox address of the exported video.
///   - optimizeForNetworkUse: The output file should be optimized for network use.
///   - filtering: Filters work to filter pixel buffer.
exporter.export(outputURL: outputURL) {
    let dest = BoxxIO(element: $0, filters: filters)
    return try? dest.output()
}

Or

exporter.export(outputURL: outputURL) { $0 ->> gauss ->> board }
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

-----

### License
Harbeth is available under the [MIT](LICENSE) license. See the [LICENSE](LICENSE) file for more info.

-----
