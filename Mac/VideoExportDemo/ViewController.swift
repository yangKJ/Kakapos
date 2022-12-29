//
//  ViewController.swift
//  VideoExportDemo
//
//  Created by Condy on 2022/12/29.
//

import Cocoa
import Harbeth
import AVKit

class ViewController: NSViewController {
    
    let videoURL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
    //let videoURL = URL(string: "https://mp4.vjshi.com/2018-03-30/1f36dd9819eeef0bc508414494d34ad9.mp4")!
    //let videoURL = URL(string: "https://mp4.vjshi.com/2020-12-01/bc8b1a8d9166d2040bd8946ad6447235.mp4")!
    
    @IBOutlet weak var playerView: AVPlayerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        setupPlayer()
        export(at: videoURL)
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
}

extension ViewController {
    func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        playerView.player = player
        player.play()
    }
}
