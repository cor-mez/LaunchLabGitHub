//
//  RollingShutterDetectorV1.swift
//  LaunchLab
//
//  RS descriptor computation + explicit impulse reasoning
//

import CoreVideo
import CoreGraphics

final class RollingShutterDetectorV1 {

    // -----------------------------------------------------------------
    // MARK: - Internal State
    // -----------------------------------------------------------------

    private var lastZMax: Float = 0

    // -----------------------------------------------------------------
    // MARK: - Reset
    // -----------------------------------------------------------------

    func reset() {
        lastZMax = 0
    }

    // -----------------------------------------------------------------
    // MARK: - Analyze
    // -----------------------------------------------------------------

    func analyze(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> RSResult {

        // -----------------------------
        // EXISTING DESCRIPTOR COMPUTE
        // -----------------------------
        // These should already be implemented in your real detector.
        // Placeholders shown for clarity.

        let zmax: Float = computeZMax(pixelBuffer: pixelBuffer, roi: roi)
        let dz: Float = zmax - lastZMax
        lastZMax = zmax

        let r2: Float = computeR2()
        let nonu: Float = computeNonUniformity()
        let lw: Float = computeLineWidth()
        let edge: Float = computeEdgeEnergy()

        // -----------------------------
        // IMPULSE DECISION (UNCHANGED)
        // -----------------------------

        let dzThreshold: Float = 1.0
        let zThreshold: Float = 2.5

        let isImpulse: Bool =
            dz > dzThreshold &&
            zmax > zThreshold

        // -----------------------------
        // EXPLICIT REJECTION REASON
        // -----------------------------

        let rejection: String
        if isImpulse {
            rejection = "none"
        } else if dz <= dzThreshold {
            rejection = "dz_too_low"
        } else if zmax <= zThreshold {
            rejection = "zmax_too_low"
        } else {
            rejection = "unknown"
        }

        return RSResult(
            zmax: zmax,
            dz: dz,
            r2: r2,
            nonu: nonu,
            lw: lw,
            edge: edge,
            isImpulse: isImpulse,
            rejectionReason: rejection
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Placeholder Computations
    // -----------------------------------------------------------------

    private func computeZMax(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> Float {
        // KEEP YOUR REAL IMPLEMENTATION
        return 0
    }

    private func computeR2() -> Float { 0 }
    private func computeNonUniformity() -> Float { 0 }
    private func computeLineWidth() -> Float { 0 }
    private func computeEdgeEnergy() -> Float { 0 }
}
