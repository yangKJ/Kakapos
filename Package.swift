// swift-tools-version:6.0
//
//  Kakapos
//
//  Copyright (c) 2021 Iker <https://github.com/yangKJ/Kakapos>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import PackageDescription

let package = Package(
    name: "Kakapos",
    platforms: [
        .iOS(.v13), .tvOS(.v12), .watchOS(.v5), .macOS(.v12)
    ],
    products: [
        .library(name: "KakaposMediaCore", targets: ["KakaposMediaCore"]),
        .library(name: "KakaposVideo", targets: ["KakaposVideo"]),
        .library(name: "KakaposTimeline", targets: ["KakaposTimeline"]),
        .library(name: "KakaposCamera", targets: ["KakaposCamera"]),
        .library(name: "Kakapos", targets: ["Kakapos"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(name: "KakaposMediaCore", path: "Sources/MediaCore"),
        .target(
            name: "KakaposVideo",
            dependencies: ["KakaposMediaCore"],
            path: "Sources/VideoEngine"
        ),
        .target(
            name: "KakaposTimeline",
            dependencies: ["KakaposMediaCore", "KakaposVideo"],
            path: "Sources/TimelineEngine"
        ),
        .target(
            name: "KakaposCamera",
            dependencies: ["KakaposMediaCore", "KakaposVideo"],
            path: "Sources/CameraEngine"
        ),
        .target(
            name: "Kakapos",
            dependencies: ["KakaposMediaCore", "KakaposVideo", "KakaposTimeline", "KakaposCamera"],
            path: "Sources/Core"
        ),
        .testTarget(
            name: "KakaposIntegrationTests",
            dependencies: ["Kakapos", "KakaposMediaCore", "KakaposVideo", "KakaposTimeline", "KakaposCamera"],
            path: "Tests/KakaposIntegrationTests"
        ),
        .testTarget(
            name: "KakaposCameraTests",
            dependencies: ["Kakapos", "KakaposMediaCore", "KakaposVideo", "KakaposTimeline", "KakaposCamera"],
            path: "Tests/KakaposCameraTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
