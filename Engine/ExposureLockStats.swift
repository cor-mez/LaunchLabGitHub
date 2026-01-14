//
//  ExposureLockStats.swift
//  LaunchLab
//
//  Pure instrumentation:
//  Verifies exposureMode, exposureDuration, and ISO remain locked.
//

import AVFoundation

final class ExposureLockStats {

    private var baselineDuration: Double?
    private var baselineISO: Float?
    private var baselineMode: AVCaptureDevice.ExposureMode?

    private let durationTolerance: Double = 1e-6
    private let isoTolerance: Float = 0.5

    private var frameIndex: Int = 0

    func captureBaseline(from device: AVCaptureDevice) {
        baselineDuration = device.exposureDuration.seconds
        baselineISO = device.iso
        baselineMode = device.exposureMode

        Log.info(
            .camera,
            String(
                format:
                "EXPOSURE_BASELINE duration=%.6f iso=%.2f mode=%@",
                baselineDuration ?? -1,
                baselineISO ?? -1,
                String(describing: baselineMode)
            )
        )
    }

    func verify(device: AVCaptureDevice) {
        frameIndex += 1
        guard let bd = baselineDuration,
              let bi = baselineISO,
              let bm = baselineMode else { return }

        let d = device.exposureDuration.seconds
        let i = device.iso
        let m = device.exposureMode

        if m != bm ||
           abs(d - bd) > durationTolerance ||
           abs(i - bi) > isoTolerance {

            Log.info(
                .camera,
                String(
                    format:
                    "EXPOSURE_DRIFT frame=%d duration=%.6f iso=%.2f mode=%@",
                    frameIndex,
                    d,
                    i,
                    String(describing: m)
                )
            )
        }

        // Periodic confirmation
        if frameIndex % 60 == 0 {
            Log.info(
                .camera,
                String(
                    format:
                    "EXPOSURE_OK frame=%d",
                    frameIndex
                )
            )
        }
    }

    func reset() {
        baselineDuration = nil
        baselineISO = nil
        baselineMode = nil
        frameIndex = 0
    }
}
