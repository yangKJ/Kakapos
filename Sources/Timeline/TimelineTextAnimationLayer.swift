//
//  TimelineTextAnimationLayer.swift
//  Kakapos
//
//  Created by Condy on 2026/6/21.
//

import Foundation
import AVFoundation
import QuartzCore

#if canImport(UIKit)
import UIKit

class TimelineTextAnimationLayer: CALayer, NSLayoutManagerDelegate {
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    private var animationLayers: [CATextLayer] = []

    var attributedText: NSAttributedString {
        get { textStorage as NSAttributedString }
        set { textStorage.setAttributedString(newValue) }
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            textContainer.size = newValue.size
            super.bounds = newValue
        }
    }

    override init() {
        super.init()
        setupTextKit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        setupTextKit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addAnimations(to layers: [CATextLayer], duration: CFTimeInterval) {
        let animationGroup = CAAnimationGroup()
        animationGroup.duration = duration
        animationGroup.beginTime = AVCoreAnimationBeginTimeAtZero
        animationGroup.fillMode = .both
        animationGroup.isRemovedOnCompletion = false
        add(animationGroup, forKey: "animationGroup")
    }

    private func setupTextKit() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = self
        textContainer.size = .zero
    }

    private func updateAnimationLayers() {
        guard !textContainer.size.equalTo(.zero), attributedText.length > 0 else { return }

        for layer in animationLayers {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        animationLayers.removeAll()
        removeAllAnimations()

        let string = attributedText.string
        string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byComposedCharacterSequences) { [weak self] _, substringRange, _, _ in
            guard let self else { return }
            let glyphRange = NSRange(substringRange, in: string)
            let textRect = self.layoutManager.boundingRect(forGlyphRange: glyphRange, in: self.textContainer)
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = textRect
            textLayer.string = self.attributedText.attributedSubstring(from: glyphRange)
            self.animationLayers.append(textLayer)
            self.addSublayer(textLayer)
        }

        addAnimations(to: animationLayers, duration: 15)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        guard textContainer != nil else { return }
        updateAnimationLayers()
    }
}

final class TimelineTextOpacityAnimationLayer: TimelineTextAnimationLayer {
    override func addAnimations(to layers: [CATextLayer], duration: CFTimeInterval) {
        var beginTime = AVCoreAnimationBeginTimeAtZero
        let beginTimeInterval = 0.125

        for layer in layers {
            let animationGroup = CAAnimationGroup()
            animationGroup.duration = duration
            animationGroup.beginTime = AVCoreAnimationBeginTimeAtZero
            animationGroup.fillMode = .both
            animationGroup.isRemovedOnCompletion = false

            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = 0.0
            opacityAnimation.toValue = 1.0
            opacityAnimation.duration = 0.125
            opacityAnimation.beginTime = beginTime
            opacityAnimation.fillMode = .both

            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0.0
            scaleAnimation.toValue = 1.0
            scaleAnimation.duration = 0.125
            scaleAnimation.beginTime = beginTime
            scaleAnimation.fillMode = .both

            animationGroup.animations = [opacityAnimation, scaleAnimation]
            layer.add(animationGroup, forKey: "animationGroup")

            beginTime += beginTimeInterval
        }
    }
}
#endif
