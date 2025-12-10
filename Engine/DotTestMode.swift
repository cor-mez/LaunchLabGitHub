import Foundation
import CoreGraphics
import CoreVideo

enum DetectorBackend {
    case cpu
    case gpuY
    case gpuCb
}

final class DotTestMode {

    static let shared = DotTestMode()

    private let detector = MetalDetector.shared
    private let cpuFast9 = CPUFast9()
    
    private var bufferExtractor = CPUFast9BufferExtractor()
    private var normalizer = CPUFast9Normalizer()
    private var comparator = CPUGPUCornerComparator()

    var backend: DetectorBackend = .gpuY
    var freeze: Bool = false

    private var roi: CGRect = .zero
    private var srScale: Float = 1.0

    private var lastCPUCorners: [CGPoint] = []
    private var lastGPUCornersY: [CGPoint] = []
    private var lastGPUCornersCb: [CGPoint] = []

    private var lastTelemetryY: MetalDetector.DetectorTelemetry?
    private var lastTelemetryCb: MetalDetector.DetectorTelemetry?

    private init() {}

    func setROI(_ r: CGRect) {
        roi = r
    }

    func setSRScale(_ s: Float) {
        srScale = s
    }

    func toggleFreeze() {
        freeze.toggle()
    }

    func run(pixelBuffer: CVPixelBuffer) {
        if freeze { return }

        switch backend {

        case .cpu:
            let buf = bufferExtractor.extractROI(pb: pixelBuffer, roi: roi)
            let norm = normalizer.normalize(buffer: buf.ptr,
                                            width: buf.width,
                                            height: buf.height)
            let result = cpuFast9.detectAndScore(src: norm.ptr,
                                                 width: buf.width,
                                                 height: buf.height)
            lastCPUCorners = result.0

        case .gpuY:
            detector.prepareFrameY(pixelBuffer, roi: roi, srScale: srScale)
            let out = detector.gpuFast9CornersYEnhanced()
            lastGPUCornersY = out.0
            lastTelemetryY = out.1

        case .gpuCb:
            detector.prepareFrameCb(pixelBuffer, roi: roi, srScale: srScale)
            let out = detector.gpuFast9CornersCbEnhanced()
            lastGPUCornersCb = out.0
            lastTelemetryCb = out.1
        }
    }

    func cpuCorners() -> [CGPoint] {
        return lastCPUCorners
    }

    func gpuCornersY() -> [CGPoint] {
        return lastGPUCornersY
    }

    func gpuCornersCb() -> [CGPoint] {
        return lastGPUCornersCb
    }

    func telemetryY() -> MetalDetector.DetectorTelemetry? {
        return lastTelemetryY
    }

    func telemetryCb() -> MetalDetector.DetectorTelemetry? {
        return lastTelemetryCb
    }

    func activeCorners() -> [CGPoint] {
        switch backend {
        case .cpu:
            return lastCPUCorners
        case .gpuY:
            return lastGPUCornersY
        case .gpuCb:
            return lastGPUCornersCb
        }
    }

    func compareCPUvsGPUY() -> CPUGPUCornerComparator.Result {
        return comparator.compare(cpu: lastCPUCorners,
                                  gpu: lastGPUCornersY)
    }
}