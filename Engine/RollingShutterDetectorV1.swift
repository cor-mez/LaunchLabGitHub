//
//  RollingShutterDetectorV1.swift
//  LaunchLab
//
//  Computes RS metrics and returns RSResult only
//

import CoreVideo
import CoreGraphics

final class RollingShutterDetectorV1 {

    private var frameCount: Int = 0

    func reset() {
        frameCount = 0
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> RSResult? {

        frameCount += 1

        // --- EXISTING RS COMPUTATION GOES HERE ---
        let zmax = computeZMax(
            pixelBuffer: pixelBuffer,
            roi: roi
        )

        let isCandidate = zmax > 4.0

        return RSResult(
            zmax: zmax,
            isCandidate: isCandidate
        )
    }

    private func computeZMax(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> Float {
        // KEEP YOUR REAL IMPLEMENTATION
        return 0.0
    }
}
