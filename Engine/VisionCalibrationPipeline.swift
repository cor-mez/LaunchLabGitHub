//
//  VisionCalibrationPipeline.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd

final class VisionCalibrationPipeline {

    private weak var controller: RSTimingCalibrationController?

    init(controller: RSTimingCalibrationController) {
        self.controller = controller
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) {
        let t = Float(timestamp)
        controller?.processFrame(pixelBuffer: pixelBuffer, timestamp: t)
    }
}