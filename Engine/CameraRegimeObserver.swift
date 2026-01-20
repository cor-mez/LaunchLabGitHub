//
//  CameraRegimeObserver.swift
//  LaunchLab
//
//  Camera Regime DISTURBANCE OBSERVER (V1)
//
//  ROLE (STRICT):
//  - Observe global photometric disturbances
//  - Emit instability events
//  - NEVER determine stability or authority
//  - All regime state lives in CameraRegimeController
//

import CoreVideo

final class CameraRegimeObserver {

    // -----------------------------------------------------------
    // MARK: - Tunables (OBSERVATIONAL)
    // -----------------------------------------------------------

    private let maxDeltaLuma: Double = 8.0

    // -----------------------------------------------------------
    // MARK: - State
    // -----------------------------------------------------------

    private var lastMeanLuma: Double?

    // -----------------------------------------------------------
    // MARK: - Lifecycle
    // -----------------------------------------------------------

    func reset() {
        lastMeanLuma = nil
    }

    /// Observes a frame and returns whether a photometric disturbance occurred.
    /// This function NEVER decides stability — only emits events.
    func observe(pixelBuffer: CVPixelBuffer) -> Bool {

        let mean = computeMeanLuma(pb: pixelBuffer)

        defer { lastMeanLuma = mean }

        guard let last = lastMeanLuma else {
            return false
        }

        let delta = abs(mean - last)
        if delta > maxDeltaLuma {
            Log.info(
                .camera,
                String(format: "camera_luma_jump delta=%.2f", delta)
            )
            return true
        }

        return false
    }

    // -----------------------------------------------------------
    // MARK: - Luma Computation (SAMPLED)
    // -----------------------------------------------------------

    private func computeMeanLuma(pb: CVPixelBuffer) -> Double {

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0 }

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        var sum: UInt64 = 0
        var count: UInt64 = 0

        // Subsample aggressively — this is global, not per-pixel
        for y in stride(from: 0, to: height, by: 4) {
            let row = base.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: 4) {
                let luma = row.load(fromByteOffset: x, as: UInt8.self)
                sum += UInt64(luma)
                count += 1
            }
        }

        return count > 0 ? Double(sum) / Double(count) : 0
    }
}
