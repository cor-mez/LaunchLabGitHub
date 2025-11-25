//
//  RSTimingCalibratedModel.swift
//  LaunchLab
//

import Foundation

/// Calibrated rolling-shutter timing model.
/// Stores a monotonic 0→1 mapping that describes the timing curve
/// for vertical scanout (top → bottom of sensor).
///
/// Model is lightweight, Codable, and loaded from disk by
/// RSTimingModelFactory.make().
public struct RSTimingCalibratedModel: Codable, Sendable {

    /// Polynomial coefficients a0 + a1*s + a2*s² + a3*s³
    public let coeffs: [Double]

    /// Full-frame readout time (seconds)
    public let readout: Float

    public init(coeffs: [Double], readout: Float) {
        self.coeffs = coeffs
        self.readout = readout
    }

    // -------------------------------------------------------------
    // MARK: - Evaluate polynomial curve
    // -------------------------------------------------------------
    /// Evaluate normalized timing fraction at s ∈ [0,1].
    @inlinable
    public func evaluate(_ s: Float) -> Double {
        let x = Double(s)
        let c = coeffs

        // Support 2–4 coefficients cleanly
        switch c.count {
        case 2:
            return c[0] + c[1] * x
        case 3:
            return c[0] + c[1] * x + c[2] * x * x
        case 4:
            return c[0] + c[1] * x + c[2] * x * x + c[3] * x * x * x
        default:
            // Fallback to linear
            return x
        }
    }

    // -------------------------------------------------------------
    // MARK: - Persistence
    // -------------------------------------------------------------
    /// Where the calibration file is stored
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("rs_timing_model.json")
    }

    /// Load calibration model from disk.
    public static func load() -> RSTimingCalibratedModel? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return nil }

        do {
            return try JSONDecoder().decode(RSTimingCalibratedModel.self, from: data)
        } catch {
            print("[RSTimingCalibratedModel] ERROR: decode failed:", error)
            return nil
        }
    }

    /// Save to disk
    public func save() {
        let url = Self.fileURL
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[RSTimingCalibratedModel] ERROR: save failed:", error)
        }
    }
}
