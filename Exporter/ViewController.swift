//
//  ViewController.swift
//  Exporter
//
//  Created by Condy on 2022/12/23.
//

import UIKit
import Photos
import AVKit
import MobileCoreServices
import Toast_Swift

class ViewController: UIViewController {
    
    lazy var videoButton: UIButton = {
        let button = UIButton.init(type: .custom)
        button.setTitle("URL Export", for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.green.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.titleLabel?.font = UIFont.systemFont(ofSize: 30)
        button.addTarget(self, action: #selector(videoAction), for: UIControl.Event.touchUpInside)
        return button
    }()
    
    lazy var photoButton: UIButton = {
        let button = UIButton.init(type: .custom)
        button.setTitle("Photo Export", for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.green.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.titleLabel?.font = UIFont.systemFont(ofSize: 30)
        button.addTarget(self, action: #selector(photoAction), for: UIControl.Event.touchUpInside)
        return button
    }()
    
    lazy var context: CIContext = {
        let eagl = EAGLContext(api: EAGLRenderingAPI.openGLES2)
        let context = CIContext(eaglContext: eagl!, options: nil)
        return context
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
    }
    
    func setupUI() {
        title = "Video Exporter"
        view.backgroundColor = UIColor.white
        view.addSubview(videoButton)
        view.addSubview(photoButton)
        NSLayoutConstraint.activate([
            videoButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            videoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            videoButton.widthAnchor.constraint(equalToConstant: 200),
            videoButton.heightAnchor.constraint(equalToConstant: 80),
            photoButton.topAnchor.constraint(equalTo: videoButton.bottomAnchor, constant: 50),
            photoButton.centerXAnchor.constraint(equalTo: videoButton.centerXAnchor),
            photoButton.widthAnchor.constraint(equalToConstant: 200),
            photoButton.heightAnchor.constraint(equalToConstant: 80),
        ])
    }
}

extension ViewController {
    
    @objc func photoAction() {
        let cameraPickerViewController = UIImagePickerController()
        cameraPickerViewController.delegate = self
        cameraPickerViewController.mediaTypes = [kUTTypeMovie as String]
        cameraPickerViewController.videoQuality = .typeMedium
        self.present(cameraPickerViewController, animated: true)
    }
    
    @objc func videoAction() {
        let url = URL(string: "https://mp4.vjshi.com/2017-11-21/7c2b143eeb27d9f2bf98c4ab03360cfe.mp4")!
        self.export(at: url)
    }
    
    func export(at url: URL) {
        let exporter = Exporter.init(videoURL: url)
        
        // Creating temp path to save the converted video
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
        let outputURL = documentsDirectory.appendingPathComponent("rendered-Video.mp4")
        
        // Check if the file already exists then remove the previous file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                //completionHandler(nil, error)
            }
        }
        
        //        let filter = CIFilter(name: "CIGaussianBlur")
        //        filter?.setValue(20, forKey: "inputRadius")
        
        let filter = CIFilter(name: "CIGammaAdjust")
        filter?.setValue(5, forKey: "inputPower")
        
        //        let filter2 = CIFilter(name: "CIWhitePointAdjust")
        //        filter2?.setValue(CIColor(color: .green), forKey: "inputColor")
        
        self.view.makeToast("Exporting..", duration: 600, position: .center)
        
        exporter.export(outputURL: outputURL, filtering: { [weak self] (buffer) in
            var image = CIImage(cvPixelBuffer: buffer)
            filter?.setValue(image, forKey: kCIInputImageKey)
            image = filter?.outputImage ?? image
            self?.context.render(image, to: buffer)
            return buffer
        }, completionHandler: { [weak self] url, _ in
            self?.view.hideAllToasts()
            let player = AVPlayer(url: url!)
            let vc = AVPlayerViewController()
            vc.player = player
            self?.present(vc, animated: true) {
                vc.player?.play()
            }
        })
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
