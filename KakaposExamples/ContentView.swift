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

struct ContentView: View {
    
    @State var showLoadingIndicator: Bool = false
    @State var isShowAlert: Bool = false
    @State var showAlertText: String = ""
    @State var player: AVPlayer?
    
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
        }
        .alert(isPresented: self.$isShowAlert) {
            Alert(title: Text(showAlertText))
        }
        .padding()
        
        ActivityIndicatorView(isVisible: $showLoadingIndicator, type: .default())
            .frame(width: 50, height: 50, alignment: .center)
            .foregroundColor(.black)
    }
    
    /// 循环播放
    func addObserver() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: player?.currentItem,
                                               queue: nil) { notif in
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
            //C7Flip(horizontal: true, vertical: true),
            //C7SoulOut(soul: 0.3),
            //MPSGaussianBlur(radius: 5),
            C7LookupTable(name: "lut_abao"),
            C7SplitScreen(type: .two),
        ]
        //let videoURL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
        //let path = Bundle.main.path(forResource: "condy_exporter_video", ofType: "mov")!
        let path = Bundle.main.path(forResource: "Skateboarding", ofType: "mp4")!
        let videoURL = NSURL.init(fileURLWithPath: path) as URL
        let exporter = Exporter.init(provider: .init(with: videoURL))
        exporter.export(options: [
            .OptimizeForNetworkUse: true,
        ], filtering: { buffer in
            let dest = BoxxIO(element: buffer, filters: filters)
            return try? dest.output()
        }, complete: { res in
            self.showLoadingIndicator = false
            switch res {
            case .success(let outputURL):
                let asset = AVURLAsset(url: outputURL, options: [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true
                ])
                let playerItem = AVPlayerItem(asset: asset)
                success(playerItem)
            case .failure(let err):
                self.showAlertText = err.localizedDescription
                self.isShowAlert = true
            }
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
