import Foundation
import CoreVideo
import MetalKit
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    private let mode = DotTestMode.shared
    private let renderer = MetalRenderer.shared
    private let router = MetalDebugRouter.shared

    private init() {}

    func processFrame(_ pb: CVPixelBuffer) {
        if mode.freeze { return }
        mode.run(pixelBuffer: pb)
    }

    func draw(in view: MTKView, surface: DotTestDebugSurface) {
        router.draw(surface, in: view)
    }

    func activeCorners() -> [CGPoint] {
        return mode.activeCorners()
    }

    func cpuCorners() -> [CGPoint] {
        return mode.cpuCorners()
    }

    func gpuCornersY() -> [CGPoint] {
        return mode.gpuCornersY()
    }

    func gpuCornersCb() -> [CGPoint] {
        return mode.gpuCornersCb()
    }

    func telemetryY() -> MetalDetector.DetectorTelemetry? {
        return mode.telemetryY()
    }

    func telemetryCb() -> MetalDetector.DetectorTelemetry? {
        return mode.telemetryCb()
    }

    func comparisonCPUvsGPUY() -> CPUGPUCornerComparator.Result {
        return mode.compareCPUvsGPUY()
    }

    func setROI(_ roi: CGRect) {
        mode.setROI(roi)
    }

    func setSRScale(_ s: Float) {
        mode.setSRScale(s)
    }

    func setBackend(_ b: DetectorBackend) {
        mode.backend = b
    }

    func toggleFreeze() {
        mode.toggleFreeze()
    }
}