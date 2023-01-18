//
//  PlayerViewController.swift
//  KakaposMacDemo
//
//  Created by Condy on 2022/12/29.
//

import Cocoa
import Harbeth
import Kakapos
import AVKit

extension ViewController {
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
        
        let gauss = MPSGaussianBlur(radius: 8)
        let board = C7Storyboard(ranks: 2)
        
        let exporter = Exporter.init(videoURL: url, delegate: self)
        exporter.export(outputURL: outputURL) { $0 ->> board ->> gauss }
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
