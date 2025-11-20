//
//  CalibrationResult.swift
//  LaunchLab
//

import Foundation
import simd

/// Persisted calibration state for LaunchLab’s Auto-Calibration v1.
/// Saved to Application Support as calibration.json.
///
/// Everything here must be deterministic and Codable.
/// No dynamic types or closures.
/// Pure data only.
///
/// Applied automatically by CameraManager to VisionPipeline:
///  • Intrinsics refinement (K)
///  • RS-timing model override
///  • Camera tilt (pitch/roll)
///  • Camera translation offset
///  • Ball distance scale
///  • Lighting gain
///  • Stability confirmation
public struct CalibrationResult: Codable {

    // ============================================================
    // MARK: - Intrinsics (Refined K)
    // ============================================================

    public let fx: Float
    public let fy: Float
    public let cx: Float
    public let cy: Float

    public let width: Int
    public let height: Int

    /// True if auto-calibration successfully refined intrinsics.
    public let intrinsicsRefined: Bool

    // ============================================================
    // MARK: - RS Timing Model
    // ============================================================

    /// Rolling-shutter scan model parameters.
    /// These are serialized so auto-cal only needs to run once per device.
    public let rsReadoutTime: Float       // seconds
    public let rsLinearity: Float         // 1.0 = linear, <1 or >1 = nonlinear curve

    /// Reconstruct a timing model compatible with RSTimingModelProtocol.
    public var rsTimingModel: RSTimingModelProtocol {
        NonlinearRSTimingModel(readout: rsReadoutTime, linearity: rsLinearity)
    }

    // ============================================================
    // MARK: - Camera Tilt Offsets
    // ============================================================

    /// Pitch offset (radians)
    public let pitch: Float

    /// Roll offset (radians)
    public let roll: Float

    // ============================================================
    // MARK: - Ball Distance Estimate
    // ============================================================

    /// Estimated camera → ball depth in meters.
    public let ballDistance: Float

    // ============================================================
    // MARK: - Camera Translation Offset
    // ============================================================

    /// Correction for small device movements within calibration session.
    public let translationOffset: SIMD3<Float>

    // ============================================================
    // MARK: - Lighting / Detector Gain
    // ============================================================

    /// Global gain applied to detector thresholds, adaptive KLT refinement.
    public let lightingGain: Float

    // ============================================================
    // MARK: - Stability Metrics
    // ============================================================

    /// Average RMS reprojection error across calibration frames.
    public let avgRPERMS: Float

    /// Average spin drift magnitude (degrees).
    public let avgSpinDrift: Float

    /// Whether calibration satisfied all stability thresholds.
    public let isStable: Bool

    // ============================================================
    // MARK: - Init
    // ============================================================

    public init(
        fx: Float,
        fy: Float,
        cx: Float,
        cy: Float,
        width: Int,
        height: Int,
        intrinsicsRefined: Bool,

        rsReadoutTime: Float,
        rsLinearity: Float,

        pitch: Float,
        roll: Float,

        ballDistance: Float,

        translationOffset: SIMD3<Float>,

        lightingGain: Float,

        avgRPERMS: Float,
        avgSpinDrift: Float,
        isStable: Bool
    ) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
        self.intrinsicsRefined = intrinsicsRefined

        self.rsReadoutTime = rsReadoutTime
        self.rsLinearity = rsLinearity

        self.pitch = pitch
        self.roll = roll

        self.ballDistance = ballDistance

        self.translationOffset = translationOffset

        self.lightingGain = lightingGain

        self.avgRPERMS = avgRPERMS
        self.avgSpinDrift = avgSpinDrift
        self.isStable = isStable
    }
}


// ============================================================
// MARK: - RSTiming Model (Codable Reconstruction)
// ============================================================

/// Nonlinear RS timing model used by CalibrationResult.
/// Fully Codable and deterministic.
public struct NonlinearRSTimingModel: RSTimingModelProtocol, Codable {

    public let readout: Float
    public let linearity: Float

    public init(readout: Float, linearity: Float) {
        self.readout = readout
        self.linearity = linearity
    }

    /// Compute per-dot timestamp using nonlinear scan curve.
    public func timestampForRow(
        _ row: Float,
        height: Float,
        frameTimestamp: Float
    ) -> Float {
        let y = max(0, min(height - 1, row))
        let frac = y / (height - 1)

        // Nonlinear curve:
        // linearity = 1.0 → linear
        // linearity > 1.0 → convex
        // linearity < 1.0 → concave
        let shaped = pow(frac, linearity)

        return frameTimestamp + shaped * readout
    }
}