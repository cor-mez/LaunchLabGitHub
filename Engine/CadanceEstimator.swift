//
//  CadenceEstimator.swift
//  LaunchLab
//
//  Cadence Truth Probe (V1)
//
//  ROLE (STRICT):
//  - Measure effective capture cadence from timestamps
//  - Declare whether the instrument is VALID or INVALID
//  - NO smoothing tricks
//  - NO authority
//  - Logs ONLY on verdict transitions
//

import Foundation

final class CadenceEstimator {

    // ---------------------------------------------------------
    // MARK: - Verdict
    // ---------------------------------------------------------

    enum CadenceVerdict: Equatable, CustomStringConvertible {
        case unknown
        case valid(fps: Double)
        case invalid(fps: Double)

        var description: String {
            switch self {
            case .unknown:
                return "unknown"
            case .valid(let fps):
                return String(format: "valid fps=%.1f", fps)
            case .invalid(let fps):
                return String(format: "invalid fps=%.1f", fps)
            }
        }
    }

    // ---------------------------------------------------------
    // MARK: - Configuration (LOCKED)
    // ---------------------------------------------------------

    /// Minimum frames before we trust cadence statistics
    private let minSamples: Int = 120

    /// Minimum FPS to be considered valid for V1
    private let minValidFPS: Double = 110.0

    /// Sliding window size
    private let windowSize: Int = 240

    // ---------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------

    private var timestamps: [Double] = []
    private(set) var estimatedFPS: Double = 0.0

    private var lastVerdict: CadenceVerdict = .unknown

    // ---------------------------------------------------------
    // MARK: - Public API
    // ---------------------------------------------------------

    func reset() {
        timestamps.removeAll()
        estimatedFPS = 0
        lastVerdict = .unknown
    }

    /// Push a new timestamp (seconds).
    /// This is the ONLY mutation point.
    func push(timestamp: Double) {

        timestamps.append(timestamp)

        if timestamps.count > windowSize {
            timestamps.removeFirst(timestamps.count - windowSize)
        }

        guard timestamps.count >= 2 else { return }

        // -----------------------------------------------------
        // Compute instantaneous cadence
        // -----------------------------------------------------

        let dt = timestamps.last! - timestamps.first!
        guard dt > 0 else { return }

        let frames = Double(timestamps.count - 1)
        estimatedFPS = frames / dt

        // -----------------------------------------------------
        // Update verdict
        // -----------------------------------------------------

        let verdict = computeVerdict()

        if verdict != lastVerdict {
            Log.info(.camera, "CADENCE_VERDICT \(verdict)")
            lastVerdict = verdict
        }
    }

    /// Current cadence verdict.
    /// Safe to read from any thread (value-type enum).
    var verdict: CadenceVerdict {
        computeVerdict()
    }

    // ---------------------------------------------------------
    // MARK: - Internal
    // ---------------------------------------------------------

    private func computeVerdict() -> CadenceVerdict {

        guard timestamps.count >= minSamples else {
            return .unknown
        }

        if estimatedFPS >= minValidFPS {
            return .valid(fps: estimatedFPS)
        } else {
            return .invalid(fps: estimatedFPS)
        }
    }
}
