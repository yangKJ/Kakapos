//
//  ViewController.swift
//  KakaposMacDemo
//
//  Created by Condy on 2022/12/29.
//

import Cocoa
import AVKit
import Harbeth
import Kakapos

class ViewController: NSViewController {
    
    let videoURL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
    //let videoURL = URL(string: "https://mp4.vjshi.com/2020-12-27/a86e0cb5d0ea55cd4864a6fc7609dce8.mp4")!
    //let videoURL = URL(string: "https://mp4.vjshi.com/2018-03-30/1f36dd9819eeef0bc508414494d34ad9.mp4")!
    //let videoURL = URL(string: "https://mp4.vjshi.com/2020-12-01/bc8b1a8d9166d2040bd8946ad6447235.mp4")!
    
    @IBOutlet weak var playerView: AVPlayerView!
    
    lazy var loader: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        setupUI()
        export(at: videoURL)
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    func setupUI() {
        view.addSubview(loader)
        NSLayoutConstraint.activate([
            loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            loader.widthAnchor.constraint(equalToConstant: 40),
            loader.heightAnchor.constraint(equalToConstant: 40),
        ])
    }
    
    func export(at url: URL) {
        // Creating temp path to save the converted video
        let outputURL: URL = {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
            let outputURL = documentsDirectory.appendingPathComponent("condy_exporter_video.mp4")
            
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
        
        loader.startAnimation(nil)
        
        let martix = C7ColorMatrix4x4(matrix: Matrix4x4.Color.gray)
        let screen = C7SplitScreen(type: .two)
        
        let exporter = Exporter.init(videoURL: url, delegate: self)
        exporter.export(outputURL: outputURL) { $0 ->> martix ->> screen }
    }
}

extension ViewController: ExporterDelegate {
    
    func export(_ exporter: Kakapos.Exporter, success videoURL: URL) {
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        playerView.player = player
        player.play()
        loader.stopAnimation(nil)
        loader.isHidden = true
    }
    
    func export(_ exporter: Kakapos.Exporter, failed error: Kakapos.Exporter.Error) {
        loader.stopAnimation(nil)
        loader.isHidden = true
    }
}
