//  VisionCalibrationPipeline.swift

import Foundation
import CoreVideo
import simd

@MainActor
final class VisionCalibrationPipeline {

    private weak var controller: RSTimingCalibrationController?

    init(controller: RSTimingCalibrationController) {
        self.controller = controller
    }

    @MainActor
    func process(pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) {
        let t = Float(timestamp)
        controller?.processFrame(pixelBuffer: pixelBuffer, timestamp: t)
    }
}
