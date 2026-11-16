// 作者：Condy
import AVFoundation
import CoreImage
import KakaposMediaCore
import KakaposVideo

/// 冻结图层的逐帧输入；与媒体解码及后续整帧效果保持独立。
struct TimelineVisualLayer {
    let identity: ObjectIdentifier
    let level: Int
    let range: CMTimeRange
    let trackID: CMPersistentTrackID?
    let image: CIImage?
    let text: TimelineTextContent?
    let components: [TimelineLayerComponent]
    let origin: CGPoint

    init(_ layer: TimelineLayer, trackID: CMPersistentTrackID?) throws {
        identity = ObjectIdentifier(layer)
        level = layer.layerLevel
        range = layer.timeRange
        self.trackID = trackID
        image = (layer as? ImageLayer).map { CIImage(cgImage: $0.image) }
        text = try (layer as? TextLayer).map(TimelineTextContent.init)
        origin = (layer as? TextLayer)?.frame.origin ?? .zero
        components = layer.evaluationComponents.isEmpty
            ? [TimelineLayerComponent(timeOffset: .zero, opacity: layer.opacity, transform: layer.transform, keyframes: layer.keyframes)]
            : layer.evaluationComponents
    }
}

/// 保留可检查的层指令；实际混合从相同的冻结求值分量和转场绑定执行。
final class TimelineVideoInstruction: AVMutableVideoCompositionInstruction, @unchecked Sendable {
    let visuals: [TimelineVisualLayer]
    let transitions: [[TimelineTransitionBinding]]
    override var containsTweening: Bool { true }
    override var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }
    override var requiredSourceTrackIDs: [NSValue] { visuals.compactMap { $0.trackID.map(NSNumber.init(value:)) } }

    init(visuals: [TimelineVisualLayer], transitions: [[TimelineTransitionBinding]]) {
        self.visuals = visuals
        self.transitions = transitions
        super.init()
    }
    required init?(coder: NSCoder) { return nil }
    override func copy(with zone: NSZone? = nil) -> Any { self }
}

enum TimelineVisualRenderer {
    private struct Group {
        var members: Set<ObjectIdentifier>
        let image: CIImage
        let order: Int
    }

    static func image(in instruction: TimelineVideoInstruction, at time: CMTime, size: CGSize,
        source: (CMPersistentTrackID) -> CVPixelBuffer?) throws -> CIImage {
        let canvas = CGRect(origin: .zero, size: size)
        let clear = CIImage(color: .clear).cropped(to: canvas)
        var groups: [Group] = []
        for (order, layer) in instruction.visuals.enumerated() where CMTimeRangeContainsTime(layer.range, time: time) {
            let input: CIImage
            if let trackID = layer.trackID {
                guard let buffer = source(trackID) else { throw MediaCoreError.pixelBufferUnavailable }
                input = CIImage(cvPixelBuffer: buffer, options: [.toneMapHDRtoSDR: false])
            } else if let text = layer.text { input = text.image(at: (time - layer.range.start).seconds) }
            else if let image = layer.image { input = image }
            else { continue }
            let opacity = layer.components.reduce(Float(1)) { $0 * $1.opacity(at: time) }
            let positioned = layer.components.enumerated().reduce(CGAffineTransform.identity) { result, entry in
                let transform = entry.element.transform(at: time)
                let local = entry.offset == layer.components.count - 1
                    ? TimelineLayerNormalizer.compose(CGAffineTransform(translationX: layer.origin.x, y: layer.origin.y), transform)
                    : transform
                return TimelineLayerNormalizer.compose(result, local)
            }
            // 时间线使用左上坐标；Core Image 使用左下坐标，需在两端转换。
            let inputFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: layer.text?.size.height ?? input.extent.height)
            let canvasFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
            let matrix = TimelineLayerNormalizer.compose(canvasFlip, TimelineLayerNormalizer.compose(positioned, inputFlip))
            let image = input.transformed(by: matrix).applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, min(opacity, 1))))
            ]).composited(over: clear).cropped(to: canvas)
            groups.append(Group(members: [layer.identity], image: image, order: order))
        }
        for bindings in instruction.transitions {
            let active: Set<ObjectIdentifier> = Set(groups.flatMap(\.members))
            let binding = bindings.first { CMTimeRangeContainsTime($0.timeRange, time: time) }
                ?? bindings.first { active.contains(ObjectIdentifier($0.source)) && active.contains(ObjectIdentifier($0.destination)) }
                ?? bindings.first { active.contains(ObjectIdentifier($0.source)) || active.contains(ObjectIdentifier($0.destination)) }
            guard let binding else { continue }
            let from = groups.firstIndex { $0.members.contains(ObjectIdentifier(binding.source)) }
            let to = groups.firstIndex { $0.members.contains(ObjectIdentifier(binding.destination)) }
            guard from != nil || to != nil, from != to else { continue }
            let a = from.map { groups[$0] }
            let b = to.map { groups[$0] }
            let progress = max(0, min(binding.transition.timingFunction.value(at: TimelineCurveSampling.progress(at: time, in: binding.transition.timeRange)), 1))
            // 在线性工作色域中插值预乘颜色和 alpha，再把结果叠到其他图层。
            let mixed = (a?.image ?? clear).applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: b?.image ?? clear, kCIInputTimeKey: progress
            ])
            for index in Set([from, to].compactMap { $0 }).sorted(by: >) { groups.remove(at: index) }
            groups.append(Group(members: (a?.members ?? []).union(b?.members ?? []), image: mixed,
                order: max(a?.order ?? -1, b?.order ?? -1)))
        }
        return groups.sorted { $0.order < $1.order }.reduce(CIImage(color: .black).cropped(to: canvas)) {
            $1.image.composited(over: $0)
        }.cropped(to: canvas)
    }
}

class TimelineVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.condy.kakapos.timeline.visual-composition")
    private let lock = NSLock()
    private var context: AVVideoCompositionRenderContext?
    private var requests: [UUID: AVAsynchronousVideoCompositionRequest] = [:]
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let imageContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!,
        .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false
    ])
    override init() {
        super.init()
        queue.setSpecific(key: queueKey, value: 1)
    }
    private func finish(_ id: UUID, _ body: () -> Void) {
        lock.lock(); let pending = requests.removeValue(forKey: id) != nil; lock.unlock()
        if pending { body() }
    }
    var outputPixelFormat: OSType { kCVPixelFormatType_32BGRA }
    var sourcePixelBufferAttributes: [String: any Sendable]? { [kCVPixelBufferPixelFormatTypeKey as String:
        [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_64RGBAHalf]] }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { [
        kCVPixelBufferPixelFormatTypeKey as String: outputPixelFormat, kCVPixelBufferMetalCompatibilityKey as String: true
    ] }
    var supportsWideColorSourceFrames: Bool { true }
    var supportsHDRSourceFrames: Bool { true }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock(); context = newRenderContext; lock.unlock()
    }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let id = UUID()
        lock.lock(); requests[id] = request; lock.unlock()
        queue.async {
            self.lock.lock(); let active = self.requests[id] != nil; let context = self.context; self.lock.unlock()
            guard active else { return }
            do {
                guard let instruction = request.videoCompositionInstruction as? TimelineVideoInstruction,
                      let context, let output = context.newPixelBuffer() else { throw MediaCoreError.pixelBufferUnavailable }
                let image = try TimelineVisualRenderer.image(in: instruction, at: request.compositionTime, size: context.size) { request.sourceFrame(byTrackID: $0) }
                let composition = context.videoComposition
                let transfer = composition.colorTransferFunction
                let colorSpace: CGColorSpace
                if transfer == AVVideoTransferFunction_ITU_R_2100_HLG || transfer == AVVideoTransferFunction_SMPTE_ST_2084_PQ {
                    guard #available(iOS 14.1, tvOS 14.2, macOS 11, watchOS 7.1, *) else { throw VideoExportProfileError.invalidHDROutput }
                    colorSpace = CGColorSpace(name: transfer == AVVideoTransferFunction_ITU_R_2100_HLG ? CGColorSpace.itur_2100_HLG : CGColorSpace.itur_2100_PQ)!
                } else if composition.colorPrimaries == AVVideoColorPrimaries_P3_D65 { colorSpace = CGColorSpace(name: CGColorSpace.displayP3)! }
                else { colorSpace = CGColorSpace(name: CGColorSpace.itur_709)! }
                self.imageContext.render(image, to: output, bounds: CGRect(origin: .zero, size: context.size), colorSpace: colorSpace)
                CVBufferSetAttachment(output, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
                CVBufferSetAttachment(output, kCVImageBufferColorPrimariesKey, (composition.colorPrimaries ?? AVVideoColorPrimaries_ITU_R_709_2) as CFString, .shouldPropagate)
                CVBufferSetAttachment(output, kCVImageBufferTransferFunctionKey, (transfer ?? AVVideoTransferFunction_ITU_R_709_2) as CFString, .shouldPropagate)
                CVBufferSetAttachment(output, kCVImageBufferYCbCrMatrixKey, (composition.colorYCbCrMatrix ?? AVVideoYCbCrMatrix_ITU_R_709_2) as CFString, .shouldPropagate)
                self.finish(id) { request.finish(withComposedVideoFrame: output) }
            } catch { self.finish(id) { request.finish(with: error) } }
        }
    }
    func cancelAllPendingVideoCompositionRequests() {
        lock.lock(); let pending = Array(requests.values); requests.removeAll(); lock.unlock()
        pending.forEach { $0.finishCancelledRequest() }
        // 返回前等待同步渲染退出；完成回调重入时不重复等待当前队列。
        if DispatchQueue.getSpecific(key: queueKey) == nil { queue.sync {} }
    }
}

final class TimelineHDRVideoCompositor: TimelineVideoCompositor, @unchecked Sendable {
    override var outputPixelFormat: OSType { kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange }
}

extension AVMutableVideoComposition {
    func configureTimelineColor(_ policy: VideoExportColorPolicy) {
        guard customVideoCompositorClass == TimelineVideoCompositor.self || customVideoCompositorClass == TimelineHDRVideoCompositor.self else { return }
        customVideoCompositorClass = policy.isHDR ? TimelineHDRVideoCompositor.self : TimelineVideoCompositor.self
        let properties = policy.colorProperties
        colorPrimaries = properties?[AVVideoColorPrimariesKey] as? String
        colorTransferFunction = properties?[AVVideoTransferFunctionKey] as? String
        colorYCbCrMatrix = properties?[AVVideoYCbCrMatrixKey] as? String
    }
}
