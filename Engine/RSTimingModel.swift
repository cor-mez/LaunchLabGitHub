//
//  RSTimingModel.swift
//  LaunchLab
//

import Foundation
import simd

// ============================================================
// MARK: - Protocol
// ============================================================

public protocol RSTimingModelProtocol {
    /// row: pixel row (0 … height-1)
    /// height: image height
    /// frameTimestamp: Double (seconds)
    func timestampForRow(
        _ row: Float,
        height: Float,
        frameTimestamp: Double
    ) -> Float
}

// ============================================================
// MARK: - Linear Model (Fallback)
// ============================================================

public final class LinearRSTimingModel: RSTimingModelProtocol {

    private let readout: Float   // seconds

    public init(readout: Float = 0.0039) {
        self.readout = readout
    }

    public func timestampForRow(
        _ row: Float,
        height: Float,
        frameTimestamp: Double
    ) -> Float {

        guard height > 1 else {
            return Float(frameTimestamp)
        }

        let y = max(0, min(height - 1, row))
        let s = y / (height - 1)       // normalized 0→1
        let dt = s * readout

        return Float(frameTimestamp) + dt
    }
}

// ============================================================
// MARK: - Calibrated RS Timing Model
// ============================================================

public final class CalibratedRSTimingModel: RSTimingModelProtocol {

    private let model: RSTimingCalibratedModel
    private let readout: Float    // seconds (e.g., 0.0038)

    public init(model: RSTimingCalibratedModel) {
        self.model = model
        self.readout = model.readout
    }

    public func timestampForRow(
        _ row: Float,
        height: Float,
        frameTimestamp: Double
    ) -> Float {

        guard height > 1 else {
            return Float(frameTimestamp)
        }

        // Normalize 0…1
        let y = max(0, min(height - 1, row))
        let s = y / (height - 1)             // normalized 0→1

        // Evaluate calibrated curve(s)
        // Curve is monotonic and outputs 0…1 timing fraction
        let curveVal = Float(model.evaluate(s))

        // Convert to seconds
        let dt = curveVal * readout

        return Float(frameTimestamp) + dt
    }
}

// ============================================================
// MARK: - RSTimingModel Factory
// ============================================================

public enum RSTimingModelFactory {

    /// Loads model from disk, else linear fallback
    public static func make() -> RSTimingModelProtocol {
        if let loaded = RSTimingCalibratedModel.load() {
            return CalibratedRSTimingModel(model: loaded)
        }
        return LinearRSTimingModel()
    }
}