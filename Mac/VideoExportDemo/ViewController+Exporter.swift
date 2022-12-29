//
//  PlayerViewController.swift
//  VideoExportDemo
//
//  Created by Condy on 2022/12/29.
//

import Cocoa
import Harbeth
import Exporter
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
        
        let gauss = MPSGaussianBlur(radius: 8)
        let board = C7Storyboard(ranks: 2)
        
        let exporter = VideoExporter.init(videoURL: url, delegate: self, commands: [])
        exporter.export(outputURL: outputURL) { $0 ->> gauss ->> board }
    }
}

extension ViewController: ExporterDelegate {
    func export(_ exporter: Exporter.VideoExporter, success videoURL: URL) {
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        playerView.player = player
        player.play()
    }
    
    func export(_ exporter: Exporter.VideoExporter, failed error: Exporter.VideoExporter.Error) {
        
    }
}
