//
//  ViewController.swift
//  VideoExportDemo
//
//  Created by Condy on 2022/12/23.
//

import UIKit
import Photos
import AVKit
import MobileCoreServices
import Toast_Swift
import Harbeth
import Kakapos

class ViewController: UIViewController {
    
    let videoURL: URL = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
    
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
    
    lazy var player: AVPlayer = {
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerView.layoutIfNeeded()
        playerLayer.frame = playerView.bounds
        playerView.layer.addSublayer(playerLayer)
        return player
    }()
    
    lazy var playerView: UIView = {
        let view = UIView.init()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemPink.withAlphaComponent(0.4)
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTapGesture)
        return view
    }()
    
    lazy var videoButton: UIButton = {
        let button = UIButton.init(type: .custom)
        button.setTitle("URL Export", for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.green.withAlphaComponent(0.5)
        button.layer.cornerRadius = 15
        button.layer.masksToBounds = true
        button.titleLabel?.font = UIFont.systemFont(ofSize: 25)
        button.addTarget(self, action: #selector(videoAction), for: UIControl.Event.touchUpInside)
        return button
    }()
    
    lazy var photoButton: UIButton = {
        let button = UIButton.init(type: .custom)
        button.setTitle("Photo Export", for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.green.withAlphaComponent(0.5)
        button.layer.cornerRadius = 15
        button.layer.masksToBounds = true
        button.titleLabel?.font = UIFont.systemFont(ofSize: 25)
        button.addTarget(self, action: #selector(photoAction), for: UIControl.Event.touchUpInside)
        return button
    }()
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player.pause()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.setupPlayer()
    }
    
    func setupUI() {
        title = "Video Exporter"
        view.backgroundColor = UIColor.white
        view.addSubview(playerView)
        view.addSubview(videoButton)
        view.addSubview(photoButton)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 3/4),
            videoButton.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 30),
            videoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            videoButton.widthAnchor.constraint(equalToConstant: 180),
            videoButton.heightAnchor.constraint(equalToConstant: 70),
            photoButton.topAnchor.constraint(equalTo: videoButton.bottomAnchor, constant: 30),
            photoButton.centerXAnchor.constraint(equalTo: videoButton.centerXAnchor),
            photoButton.widthAnchor.constraint(equalToConstant: 180),
            photoButton.heightAnchor.constraint(equalToConstant: 70),
        ])
    }
    
    func setupPlayer() {
        //player.play()
        let _ = player
    }
}

extension ViewController {
    func export(at url: URL) {
        self.view.makeToast("Exporting..", duration: 600, position: .center)
        
        let filters: [C7FilterProtocol] = [
            C7Flip(horizontal: true, vertical: false),
            C7SoulOut(soul: 0.3),
            MPSGaussianBlur(radius: 5),
            C7ColorConvert(with: .gray),
        ]
        
        let exporter = Exporter.init(videoURL: url, delegate: self)
        exporter.export(outputURL: outputURL) {
            let dest = BoxxIO(element: $0, filters: filters)
            return try? dest.output()
        }
    }
}

extension ViewController {
    
    @objc func handleSingleTap() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    
    @objc func photoAction() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.mediaTypes = [kUTTypeMovie as String]
        picker.videoQuality = .typeMedium
        self.present(picker, animated: true)
    }
    
    @objc func videoAction() {
        self.export(at: videoURL)
    }
}

extension ViewController: ExporterDelegate {
    
    func export(_ exporter: Kakapos.Exporter, success videoURL: URL) {
        self.view.hideAllToasts()
        let player = AVPlayer(url: videoURL)
        let vc = AVPlayerViewController()
        vc.player = player
        self.present(vc, animated: true) {
            vc.player?.play()
        }
    }
    
    func export(_ exporter: Kakapos.Exporter, failed error: Kakapos.Exporter.Error) {
        self.view.hideAllToasts()
        print(error.localizedDescription)
    }
}

extension ViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let originalURL = info[.mediaURL] as? URL else {
            return
        }
        self.dismiss(animated: true) { [weak self] in
            self?.export(at: originalURL)
        }
    }
}
