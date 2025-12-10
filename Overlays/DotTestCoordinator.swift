import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import Combine
import Accelerate

enum DetectorBackend: String, CaseIterable, Hashable {
    case cpu
    case gpuY
    case gpuCb
}

@MainActor
final class DotTestCoordinator: ObservableObject {

    @Published var liveBuffer: CVPixelBuffer?
    @Published var frozenBuffer: CVPixelBuffer?
    @Published var currentROI: CGRect?

    @Published var preFast9Buffer: vImage_Buffer?
    @Published var srFast9Buffer: vImage_Buffer?

    @Published var detectedCountCPU: Int = 0
    @Published var detectedCountGPU: Int = 0
    @Published var averageBrightness: Double = 0
    @Published var roiSize: CGSize = .zero

    let overlayLayer = DotTestOverlayLayer()

    weak var camera: CameraManager?
    var onDimensions: ((Int, Int) -> Void)?
    private var cancellable: AnyCancellable?

    private let gpu = MetalDetector()

    var isFrozen = false

    func attach(camera: CameraManager) {
        self.camera = camera
        cancellable = camera.$latestWeakPixelBuffer
            .receive(on: RunLoop.main)
            .sink { [weak self] wpb in
                guard let self, let pb = wpb.buffer else { return }
                let w = CVPixelBufferGetWidth(pb)
                let h = CVPixelBufferGetHeight(pb)
                self.onDimensions?(w, h)
                if !self.isFrozen { self.liveBuffer = pb }
            }
    }

    func freezeFrame() {
        guard let pb = liveBuffer else { return }
        frozenBuffer = pb
        isFrozen = true
    }

    func unfreeze() {
        frozenBuffer = nil
        isFrozen = false
        if var p = preFast9Buffer { p.freeSelf() }
        if var s = srFast9Buffer { s.freeSelf() }
        preFast9Buffer = nil
        srFast9Buffer = nil
        detectedCountCPU = 0
        detectedCountGPU = 0
        averageBrightness = 0
        roiSize = .zero
        currentROI = nil
        overlayLayer.update(pointsCPU: [], pointsGPU: [], bufferSize: .zero, roiRect: nil)
    }

    func runDetection(
        with config: DotDetectorConfig,
        roiScale: CGFloat,
        backend: DetectorBackend
    ) {
        guard let buffer = frozenBuffer ?? liveBuffer else { return }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)

        let side = CGFloat(min(w, h)) * roiScale
        let roi = CGRect(
            x: CGFloat(w) * 0.5 - side * 0.5,
            y: CGFloat(h) * 0.5 - side * 0.5,
            width: side,
            height: side
        )

        currentROI = roi
        roiSize = roi.size

        switch backend {
        case .cpu:
            runCPU(buffer: buffer, roi: roi, width: w, height: h, config: config)
        case .gpuY:
            runGPU_Y(buffer: buffer, roi: roi, width: w, height: h, config: config)
        case .gpuCb:
            runGPU_Cb(buffer: buffer, roi: roi, width: w, height: h, config: config)
        }
    }
}
extension DotTestCoordinator {

    private func runCPU(
        buffer: CVPixelBuffer,
        roi: CGRect,
        width: Int,
        height: Int,
        config: DotDetectorConfig
    ) {
        let detector = DotDetector(config: config)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let (points, _, preBuf, srBuf) =
                detector.detectWithFAST9Buffers(pixelBuffer: buffer, roi: roi)

            let bright = self.computeBrightness(buffer: buffer, roi: roi)

            DispatchQueue.main.async {
                if var p = self.preFast9Buffer { p.freeSelf() }
                if var s = self.srFast9Buffer { s.freeSelf() }
                self.preFast9Buffer = preBuf
                self.srFast9Buffer = srBuf
                self.detectedCountCPU = points.count
                self.averageBrightness = bright
                self.overlayLayer.update(
                    pointsCPU: points,
                    pointsGPU: [],
                    bufferSize: CGSize(width: width, height: height),
                    roiRect: roi
                )
            }
        }
    }

    private func runGPU_Y(
        buffer: CVPixelBuffer,
        roi: CGRect,
        width: Int,
        height: Int,
        config: DotDetectorConfig
    ) {
        preFast9Buffer = nil
        srFast9Buffer = nil
        let sr = config.srScaleOverride

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            self.gpu.prepareFrameY(
                buffer,
                roi: roi,
                srScale: sr,
                threshold: Float(config.fast9Threshold)
            )

            let points = self.gpu.gpuFast9CornersY()
            let bright = self.computeBrightness(buffer: buffer, roi: roi)

            DispatchQueue.main.async {
                self.detectedCountGPU = points.count
                self.averageBrightness = bright
                self.overlayLayer.update(
                    pointsCPU: [],
                    pointsGPU: points,
                    bufferSize: CGSize(width: width, height: height),
                    roiRect: roi
                )
            }
        }
    }

    private func runGPU_Cb(
        buffer: CVPixelBuffer,
        roi: CGRect,
        width: Int,
        height: Int,
        config: DotDetectorConfig
    ) {
        preFast9Buffer = nil
        srFast9Buffer = nil
        let sr = config.srScaleOverride

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            self.gpu.prepareFrameCb(
                buffer,
                roi: roi,
                srScale: sr,
                threshold: Float(config.fast9Threshold),
                config: config
            )

            let points = self.gpu.gpuFast9CornersCb()
            let bright = self.computeBrightness(buffer: buffer, roi: roi)

            DispatchQueue.main.async {
                self.detectedCountGPU = points.count
                self.averageBrightness = bright
                self.overlayLayer.update(
                    pointsCPU: [],
                    pointsGPU: points,
                    bufferSize: CGSize(width: width, height: height),
                    roiRect: roi
                )
            }
        }
    }

    private func computeBrightness(buffer: CVPixelBuffer, roi: CGRect) -> Double {
        var sum = 0.0
        var count = 0

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let rb = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for y in Int(roi.minY)..<Int(roi.maxY) {
                let row = ptr + y * rb
                for x in Int(roi.minX)..<Int(roi.maxX) {
                    sum += Double(row[x])
                    count += 1
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        if count == 0 { return 0 }
        return sum / (Double(count) * 255.0)
    }
}
