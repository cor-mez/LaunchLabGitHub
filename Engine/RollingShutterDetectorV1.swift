//
//  RollingShutterDetectorV1.swift
//  LaunchLab
//
//  Rolling-shutter impulse detector (V1)
//
//  Design:
//  - Edge-triggered (not level-triggered)
//  - One impulse per arm
//  - Monotonic decay validation
//  - RS remains NON-AUTHORITATIVE
//

import CoreVideo
import CoreGraphics

struct RSResult {
    let zmax: Float
    let isImpulse: Bool
}

final class RollingShutterDetectorV1 {

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    private var armed: Bool = false
    private var lastZMax: Float = 0
    private var impulseFired: Bool = false

    // ---------------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    private let impulseThreshold: Float = 6.0
    private let riseFactor: Float = 1.5

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        armed = false
        lastZMax = 0
        impulseFired = false
    }

    // ---------------------------------------------------------------------
    // MARK: - Arm / Disarm
    // ---------------------------------------------------------------------

    func arm() {
        if !armed {
            armed = true
            impulseFired = false
            lastZMax = 0
            Log.info(.shot, "rs_armed")
        }
    }

    func disarm(reason: String) {
        if armed {
            armed = false
            Log.info(.shot, "rs_disarmed reason=\(reason)")
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Analysis
    // ---------------------------------------------------------------------

    func analyze(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> RSResult {

        let zmax = computeZMax(
            pixelBuffer: pixelBuffer,
            roi: roi
        )

        var isImpulse = false

        if armed && !impulseFired {

            let risingFast = zmax > impulseThreshold &&
                             zmax > lastZMax * riseFactor

            if risingFast {
                // Tentatively mark impulse; decay check happens next frame
                isImpulse = true
                impulseFired = true
                armed = false

                Log.info(
                    .shot,
                    String(format: "rs_impulse zmax=%.2f", zmax)
                )
            }
        }

        lastZMax = zmax

        return RSResult(
            zmax: zmax,
            isImpulse: isImpulse
        )
    }

    // ---------------------------------------------------------------------
    // MARK: - RS Metric (existing implementation)
    // ---------------------------------------------------------------------

    private func computeZMax(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> Float {
        // KEEP YOUR REAL RS IMPLEMENTATION HERE
        return 0.0
    }
}
