//
//  AutoCalibration.swift
//  LaunchLab
//

import Foundation
import simd

// ============================================================
// MARK: - Internal Calibration State
// ============================================================

/// Internal persistent calibration values.
fileprivate struct CalibrationState {
    var roll: Float = 0
    var pitch: Float = 0
    var yawOffset: Float = 0
    var cameraToTeeDistance: Float = 1.0
    var launchOrigin: SIMD3<Float> = .zero
    var worldAlignmentR: simd_float3x3 = matrix_identity_float3x3
    var isValid: Bool = false
}

// ============================================================
// MARK: - AutoCalibration
// ============================================================

final class AutoCalibration {

    static let shared = AutoCalibration()

    private var state = CalibrationState()

    private var recentDirections: [SIMD3<Float>] = []
    private let maxDirectionSamples = 60
    private var targetLineYaw: Float = 0

    private init() {}

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------

    /// Light calibration (continuous) — yaw alignment only.
    func processFrame(_ frame: VisionFrameData) {
        guard let rspnp = frame.rspnp, rspnp.isValid else { return }
        refineYawSlidingWindow(rspnp.v)
    }

    /// Heavy calibration — run once over a batch of frames.
    func runCalibration(
        frames: [VisionFrameData],
        completion: @escaping (CalibrationResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = self.computeHeavyCalibration(frames) else {
                return
            }
            self.apply(result)
            completion(result)
        }
    }

    /// Retrieves the current internal calibration state.
    func currentCalibration() -> CalibrationResult? {
        guard state.isValid else { return nil }
        return CalibrationResult(
            roll: state.roll,
            pitch: state.pitch,
            yawOffset: state.yawOffset,
            cameraToTeeDistance: state.cameraToTeeDistance,
            launchOrigin: state.launchOrigin,
            worldAlignmentR: state.worldAlignmentR
        )
    }

    func setTargetLine(angleRadians: Float) {
        targetLineYaw = angleRadians
    }

    // ------------------------------------------------------------
    // MARK: - Heavy Calibration
    // ------------------------------------------------------------

    private func computeHeavyCalibration(_ frames: [VisionFrameData])
        -> CalibrationResult?
    {
        let validFrames = frames.compactMap { f in
            (f.rspnp?.isValid == true) ? f : nil
        }
        guard validFrames.count >= 8 else { return nil }

        let rp = estimateRollPitch(from: validFrames)
        let yaw = estimateYawAlignment(from: validFrames)
        let dist = estimateTeeDistance(from: validFrames)
        let origin = estimateLaunchOrigin(from: validFrames)
        let worldR = buildWorldAlignment(rotationYaw: yaw)

        return CalibrationResult(
            roll: rp.roll,
            pitch: rp.pitch,
            yawOffset: yaw,
            cameraToTeeDistance: dist,
            launchOrigin: origin,
            worldAlignmentR: worldR
        )
    }

    private func apply(_ r: CalibrationResult) {
        state.roll = r.roll
        state.pitch = r.pitch
        state.yawOffset = r.yawOffset
        state.cameraToTeeDistance = r.cameraToTeeDistance
        state.launchOrigin = r.launchOrigin
        state.worldAlignmentR = r.worldAlignmentR
        state.isValid = true
    }

    // ------------------------------------------------------------
    // MARK: - Light Calibration
    // ------------------------------------------------------------

    private func refineYawSlidingWindow(_ v: SIMD3<Float>) {
        let h = SIMD3<Float>(v.x, 0, v.z)
        let mag = simd_length(h)
        if mag < 0.001 { return }

        let d = h / mag
        recentDirections.append(d)
        if recentDirections.count > maxDirectionSamples {
            recentDirections.removeFirst()
        }

        let avg = recentDirections.reduce(.zero, +) / Float(recentDirections.count)
        let yaw = atan2(avg.x, avg.z)

        state.yawOffset = yaw - targetLineYaw
        state.worldAlignmentR = buildWorldAlignment(rotationYaw: state.yawOffset)
    }

    // ------------------------------------------------------------
    // MARK: - Estimation Helpers
    // ------------------------------------------------------------

    private func estimateRollPitch(from frames: [VisionFrameData])
        -> (roll: Float, pitch: Float)
    {
        var count: Float = 0
        var sumR = simd_float3x3(0)   // ← FIXED

        for f in frames {
            if let R = f.rspnp?.R {
                sumR += R
                count += 1
            }
        }
        let Ravg = sumR * (1.0 / count)
        let pitch = -asin(Ravg.columns.0.z)
        let roll  = atan2(Ravg.columns.1.z, Ravg.columns.2.z)
        return (roll, pitch)
    }

    private func estimateYawAlignment(from frames: [VisionFrameData]) -> Float {
        var angles: [Float] = []
        for f in frames {
            if let v = f.rspnp?.v {
                let h = SIMD3<Float>(v.x, 0, v.z)
                let mag = simd_length(h)
                if mag > 0.001 { angles.append(atan2(h.x, h.z)) }
            }
        }
        guard !angles.isEmpty else { return 0 }
        return angles.reduce(0, +) / Float(angles.count) - targetLineYaw
    }

    private func estimateTeeDistance(from frames: [VisionFrameData]) -> Float {
        let mags = frames.compactMap { f in
            f.rspnp.map { simd_length($0.t) }
        }
        guard !mags.isEmpty else { return 1 }
        return mags.reduce(0,+) / Float(mags.count)
    }

    private func estimateLaunchOrigin(from frames: [VisionFrameData]) -> SIMD3<Float> {
        let origins = frames.compactMap { f in
            f.rspnp.map { -$0.t }
        }
        guard !origins.isEmpty else { return .zero }
        return origins.reduce(.zero, +) / Float(origins.count)
    }

    // ------------------------------------------------------------
    // MARK: - Transform Builders
    // ------------------------------------------------------------

    private func buildWorldAlignment(rotationYaw yaw: Float) -> simd_float3x3 {
        let c = cos(yaw)
        let s = sin(yaw)
        return simd_float3x3(
            SIMD3<Float>( c, 0, s),
            SIMD3<Float>( 0, 1, 0),
            SIMD3<Float>(-s, 0, c)
        )
    }

    private func buildRollPitchMatrix(roll: Float, pitch: Float)
        -> simd_float3x3
    {
        let cr = cos(roll), sr = sin(roll)
        let cp = cos(pitch), sp = sin(pitch)

        let Rroll = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cr, -sr),
            SIMD3<Float>(0, sr, cr)
        )

        let Rpitch = simd_float3x3(
            SIMD3<Float>(cp, 0, sp),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-sp, 0, cp)
        )

        return Rpitch * Rroll
    }
}
