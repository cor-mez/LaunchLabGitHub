//
//  RollingShutterDetectorV2.swift
//  LaunchLab
//
//  Rolling-shutter observability with row-adjacent structure.
//  This file makes NO claims about “ball” or “impact”.
//  It only reports what the sensor appears to be doing.
//

import Foundation
import CoreVideo
import Accelerate

final class RollingShutterDetectorV2 {

    // -------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------

    private var lastZMax: Float = 0

    func reset() {
        lastZMax = 0
    }

    // -------------------------------------------------------------
    // MARK: - Main entry
    // -------------------------------------------------------------

    func analyze(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect,
        timestamp: Double
    ) -> RSResult {

        // ---------------------------------------------------------
        // 1. Compute row energy (caller already validated ROI)
        // ---------------------------------------------------------

        let rowEnergy = computeRowEnergy(
            pixelBuffer: pixelBuffer,
            roi: roi
        )

        guard rowEnergy.count >= 8 else {
            return RSResult(
                zmax: 0,
                dz: 0,
                r2: 0,
                nonu: 0,
                lw: 0,
                edge: 0,
                rowAdjCorrelation: 0,
                bandingScore: 0,
                isImpulse: false,
                rejectionReason: "row_energy_insufficient"
            )
        }

        // ---------------------------------------------------------
        // 2. Scalar energy
        // ---------------------------------------------------------

        let zmax = rowEnergy.max() ?? 0
        let dz   = zmax - lastZMax
        lastZMax = zmax

        // ---------------------------------------------------------
        // 3. Row-adjacent correlation (local coherence)
        // ---------------------------------------------------------

        var adjCorrNumerator: Float = 0
        var adjCorrDenA: Float = 0
        var adjCorrDenB: Float = 0

        for i in 0..<(rowEnergy.count - 1) {
            let a = rowEnergy[i]
            let b = rowEnergy[i + 1]
            adjCorrNumerator += a * b
            adjCorrDenA += a * a
            adjCorrDenB += b * b
        }

        let rowAdjCorrelation: Float = {
            let denom = sqrt(adjCorrDenA * adjCorrDenB)
            return denom > 0 ? adjCorrNumerator / denom : 0
        }()

        // ---------------------------------------------------------
        // 4. Flicker banding score (FFT periodicity proxy)
        // ---------------------------------------------------------

        let n = rowEnergy.count

        // FFT requires power-of-two length
        guard (n & (n - 1)) == 0 else {
            return RSResult(
                zmax: zmax,
                dz: dz,
                r2: 0,
                nonu: 0,
                lw: 0,
                edge: 0,
                rowAdjCorrelation: rowAdjCorrelation,
                bandingScore: 0,
                isImpulse: false,
                rejectionReason: "fft_length_not_power_of_two"
            )
        }

        let log2n = vDSP_Length(log2(Float(n)))

        var real = rowEnergy
        var imag = [Float](repeating: 0, count: n)

        var split = DSPSplitComplex(
            realp: &real,
            imagp: &imag
        )

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return RSResult(
                zmax: zmax,
                dz: dz,
                r2: 0,
                nonu: 0,
                lw: 0,
                edge: 0,
                rowAdjCorrelation: rowAdjCorrelation,
                bandingScore: 0,
                isImpulse: false,
                rejectionReason: "fft_setup_failed"
            )
        }

        vDSP_fft_zrip(
            fftSetup,
            &split,
            1,
            log2n,
            FFTDirection(FFT_FORWARD)
        )

        var mags = [Float](repeating: 0, count: n / 2)
        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(mags.count))
        vDSP_destroy_fftsetup(fftSetup)

        let bandingScore = mags.max() ?? 0

        // ---------------------------------------------------------
        // 5. Heuristic classification (explicitly provisional)
        // ---------------------------------------------------------

        let isImpulse =
            zmax > 1.0 &&
            abs(dz) > 0.2 &&
            rowAdjCorrelation > 0.5 &&
            bandingScore < 10_000   // flicker tends to spike FFT peaks

        let rejectionReason: String = {
            if zmax <= 1.0 { return "low_energy" }
            if abs(dz) <= 0.2 { return "low_derivative" }
            if rowAdjCorrelation <= 0.5 { return "low_row_coherence" }
            if bandingScore >= 10_000 { return "banding_detected" }
            return "accepted"
        }()

        return RSResult(
            zmax: zmax,
            dz: dz,
            r2: 0,
            nonu: 0,
            lw: 0,
            edge: 0,
            rowAdjCorrelation: rowAdjCorrelation,
            bandingScore: bandingScore,
            isImpulse: isImpulse,
            rejectionReason: rejectionReason
        )
    }

    // -------------------------------------------------------------
    // MARK: - Row energy extraction
    // -------------------------------------------------------------

    private func computeRowEnergy(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> [Float] {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return []
        }

        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let x0 = max(0, Int(roi.minX))
        let x1 = min(width - 1, Int(roi.maxX))
        let y0 = max(0, Int(roi.minY))
        let y1 = min(height - 1, Int(roi.maxY))

        var energy = [Float]()

        for y in y0..<y1 {
            let rowPtr = base.advanced(by: y * stride)
            var sum: Float = 0

            for x in x0..<x1 {
                let px = rowPtr.load(fromByteOffset: x, as: UInt8.self)
                sum += Float(px)
            }

            energy.append(sum)
        }

        return energy
    }
}
