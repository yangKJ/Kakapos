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
import ActivityIndicatorView
import Photos

struct ContentView: View {
    
    @State var showLoadingIndicator: Bool = false
    @State var isShowAlert: Bool = false
    @State var showAlertText: String = ""
    @State var player: AVPlayer?
    @State var outputURL: URL?
    
    var body: some View {
        VStack {
            VideoPlayer(player: player, videoOverlay: {
                VStack(alignment: .leading) {
                    Text("Corona Beer Advertisement")
                        .foregroundColor(Color.gray)
                        .bold()
                        .font(Font.title2)
                        .padding(.all, 20)
                    Spacer()
                }
            })
            .padding()
            .frame(width: 400, height: 400, alignment: .center)
            .onAppear {
                addObserver()
            }
            .onDisappear {
                removeObserver()
            }
            
            Text("Hello World")
                .padding()
            
            Label {
                Text("Do Something")
                    .font(.title3)
                    .foregroundColor(.blue)
            } icon: {
                
            }.onTapGesture {
                videoExport(success: { playerItem in
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                })
            }
            .padding()
            
            Button(action: {
                guard let outputURL = outputURL else {
                    return
                }
                requestLibraryAuthorization { _ in
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                    }, completionHandler: { _, _ in
                        
                    })
                }
            }, label: {
                Text("Save To Library")
            })
        }
        .alert(isPresented: self.$isShowAlert) {
            Alert(title: Text(showAlertText))
        }
        .padding()
        
        ActivityIndicatorView(isVisible: $showLoadingIndicator, type: .growingCircle)
            .frame(width: 80, height: 80, alignment: .center)
            .foregroundColor(.black)
    }
    
    /// 循环播放
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
        self.showLoadingIndicator = true
        self.player?.pause()
        
        let filters: [C7FilterProtocol] = [
            C7LookupTable(name: "lut_abao"),
            C7SplitScreen(type: .two),
        ]
        let filters2: [C7FilterProtocol] = [
            C7Flip(horizontal: true, vertical: true),
            C7SoulOut(soul: 0.3),
        ]
        //let videoURL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
        //let path = Bundle.main.path(forResource: "condy_exporter_video", ofType: "mov")!
        let path = Bundle.main.path(forResource: "Skateboarding", ofType: "mp4")!
        let videoURL = NSURL.init(fileURLWithPath: path) as URL
        let filtering = FilterInstruction { buffer, time, callback in
            if time >= 0, time < 10 {
                let dest = HarbethIO(element: buffer, filters: filters)
                dest.transmitOutput(success: callback)
            } else {
                let dest = HarbethIO(element: buffer, filters: filters2)
                dest.transmitOutput(success: callback)
            }
        }
        let exporter = VideoX.init(provider: .init(with: videoURL))
        let _ = exporter.export(options: [
            .OptimizeForNetworkUse: true,
            .ExportSessionTimeRange: TimeRangeType.range(5...28.0),
        ], instructions: [filtering], complete: { res in
            self.showLoadingIndicator = false
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
            print("Progress \(pro)")
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
