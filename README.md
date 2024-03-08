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

- Create the video exporter provider.

```
let provider = Exporter.Provider.init(with: ``URL Link``)

Or

let provider = Exporter.Provider.init(with: ``AVAsset``)
```

- Convert video and then add filters, convert buffer.

```
let filters: [C7FilterProtocol] = [
    C7Flip(horizontal: true, vertical: false),
    C7ColorConvert(with: .gray),
    C7SoulOut(soul: 0.3),
    MPSGaussianBlur(radius: 5),
]

let exporter = Exporter.init(provider: provider)

/// Export the video after add the filter.
/// - Parameters:
///   - options: Setup other parameters about export video.
///   - filtering: Filters work to filter pixel buffer.
///   - complete: The conversion is complete, including success or failure.
exporter.export(options: [
    .OptimizeForNetworkUse: true,
    .ExportSessionTimeRange: TimeRangeType.range(10...28.0),
], filtering: { buffer, callback in
    let dest = BoxxIO(element: buffer, filters: filters)
    dest.transmitOutput(success: callback)
}, complete: { res in
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

-----

### License
Harbeth is available under the [MIT](LICENSE) license. See the [LICENSE](LICENSE) file for more info.

-----
