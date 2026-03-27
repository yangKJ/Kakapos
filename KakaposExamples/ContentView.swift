//
//  ContentView.swift
//  KakaposExamples
//
//  Created by Condy on 2023/7/31.
//

import SwiftUI
import AVFoundation
import AVKit
import Harbeth
import Photos

struct ContentView: View {
    
    @State var showLoadingIndicator: Bool = false
    @State var isShowAlert: Bool = false
    @State var showAlertText: String = ""
    @State var player: AVPlayer?
    @State var outputURL: URL?
    @State var selectedVideo: String = "mp4"
    @State var processingProgress: Float = 0.0
    @State var isPlaying: Bool = false
    @State var processingTime: String = ""
    @State var startTime: Date? = nil
    @State var selectedRotation: RotationAngle = .angle0
    
    let videoOptions = ["mov", "mp4"]
    let rotationOptions: [(String, RotationAngle)] = [
        ("0°", .angle0),
        ("90°", .angle90),
        ("180°", .angle180),
        ("270°", .angle270)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("VideoX Test App")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.top, 16)
                
                ZStack {
                    VideoPlayer(player: player)
                        .aspectRatio(4/3, contentMode: .fit)
                        .cornerRadius(8)
                        .shadow(radius: 8)
                        .padding(.horizontal, 16)
                    
                    if showLoadingIndicator {
                        ZStack {
                            Color.black.opacity(0.7)
                                .cornerRadius(8)
                            VStack(spacing: 16) {
                                ProgressView(value: processingProgress, total: 1.0)
                                    .frame(width: 250)
                                    .foregroundColor(.white)
                                    .scaleEffect(1.2)
                                Text("Loading... \(Int(processingProgress * 100))%")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                        .aspectRatio(4/3, contentMode: .fit)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                        .animation(.easeInOut, value: showLoadingIndicator)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Video:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Picker("Video", selection: $selectedVideo) {
                        ForEach(videoOptions, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotation:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Picker("Rotation", selection: $selectedRotation) {
                        ForEach(rotationOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }
                .padding(.top, -16)
                .padding(.horizontal, 16)
                
                HStack(spacing: 12) {
                    Button(action: {
                        videoExport(success: { playerItem in
                            self.player = AVPlayer(playerItem: playerItem)
                            self.player?.play()
                            self.isPlaying = true
                            self.addObserver()
                        })
                    }) {
                        Text("Process Video")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(LinearGradient(gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]), startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: {
                        guard let outputURL = outputURL else {
                            showAlertText = "No video processed yet"
                            isShowAlert = true
                            return
                        }
                        requestLibraryAuthorization { status in
                            if status == .authorized {
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                                }, completionHandler: { success, error in
                                    DispatchQueue.main.async {
                                        if success {
                                            showAlertText = "Video saved to library"
                                        } else {
                                            showAlertText = "Failed to save video: \(error?.localizedDescription ?? "Unknown error")"
                                        }
                                        isShowAlert = true
                                    }
                                })
                            } else {
                                showAlertText = "Need permission to save video to library"
                                isShowAlert = true
                            }
                        }
                    }) {
                        Text("Save To Library")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(LinearGradient(gradient: Gradient(colors: [.green, .green.opacity(0.8)]), startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 16)
                
                if let outputURL = outputURL {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Video Info:")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Output: \(outputURL.lastPathComponent)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("Status: Processed")
                                .font(.subheadline)
                                .foregroundColor(.green)
                            if !processingTime.isEmpty {
                                Text("Processing Time: \(processingTime)")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
            .alert(isPresented: $isShowAlert) {
                Alert(
                    title: Text("VideoX Test"),
                    message: Text(showAlertText),
                    dismissButton: .default(Text("OK"))
                )
            }
            .edgesIgnoringSafeArea(.bottom)
        }
    }
    
    func addObserver() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: nil) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
    
    func removeObserver() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    func videoExport(success: @escaping (AVPlayerItem) -> Void) {
        if showLoadingIndicator { return }
        self.showLoadingIndicator = true
        self.player?.pause()
        self.startTime = Date()
        self.processingTime = ""
        
        var filters1: [C7FilterProtocol] = [
            C7LookupTable(name: "lut_abao"),
            C7Mirror(),
            C7Brightness(brightness: 0.0),
            C7Contrast(contrast: 0.9),
        ]
        let filters2: [C7FilterProtocol] = [
            C7CombinationHDRBoost()
        ]
        
        if selectedVideo == "mov" {
            filters1.append(C7Storyboard(ranks: 2))
        }
        
        let (fileName, fileExtension) = selectedVideo == "mov" ? ("IMG_3156", "MOV") : ("IMG_1388", "mp4")
        guard let path = Bundle.main.path(forResource: fileName, ofType: fileExtension) else {
            self.showLoadingIndicator = false
            self.showAlertText = "Video file not found"
            self.isShowAlert = true
            return
        }
        //let videoURL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
        let videoURL = URL.init(fileURLWithPath: path)
        let filtering = FilterInstruction { buffer, time, callback in
            if time >= 0, time < 3 {
                buffer.kaka.filtering(with: filters1, callback: callback)
            } else {
                let dest = HarbethIO(element: buffer, filters: filters2)
                dest.transmitOutput(success: callback)
            }
        }
        let textWatermark = WatermarkInstruction(
            type: .text("Kakapos", font: .boldSystemFont(ofSize: 120), color: .red),
            position: .bottomRight,
            margin: 20,
            opacity: 0.8,
        )
        
        // 创建指令数组
        var instructions: [CompositionInstruction] = [filtering, textWatermark]
        
        // 如果选择了非0度旋转，添加旋转指令
        if selectedRotation != .angle0 {
            let rotateInstruction = RotateInstruction(rotationAngle: selectedRotation)
            instructions.insert(rotateInstruction, at: 0)
        }
        
        let exporter = VideoX.init(provider: .init(with: videoURL))
        let _ = exporter.export(options: [
            .OptimizeForNetworkUse: true,
            .ExportSessionTimeRange: TimeRangeType.range(2...20.0),
        ], instructions: instructions, complete: { res in
            self.showLoadingIndicator = false
            if let startTime = self.startTime {
                let elapsedTime = Date().timeIntervalSince(startTime)
                self.processingTime = String(format: "%.2f seconds", elapsedTime)
            }
            switch res {
            case .success(let outputURL):
                self.outputURL = outputURL
                let asset = AVURLAsset(url: outputURL, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true
                ])
                let playerItem = AVPlayerItem(asset: asset)
                success(playerItem)
            case .failure(let err):
                self.showAlertText = err.localizedDescription
                self.isShowAlert = true
            }
        }, progress: { pro in
            DispatchQueue.main.async {
                self.processingProgress = pro
            }
        })
    }
    
    func requestLibraryAuthorization(_ handler: @escaping (PHAuthorizationStatus) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .authorized {
            handler(status)
        } else {
            PHPhotoLibrary.requestAuthorization { (status) in
                DispatchQueue.main.async {
                    handler(status)
                }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
