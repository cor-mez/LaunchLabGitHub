//
//  PresenceAuthorityGate.swift
//  LaunchLab
//
//  Presence Observability (V1)
//
//  ROLE (STRICT):
//  - Observe evidence related to object presence
//  - Emit factual signals only (no decisions, no phases)
//  - NEVER authorize, gate, arm, or finalize
//  - All authority lives in ShotLifecycleController
//

import Foundation
import CoreGraphics

// ---------------------------------------------------------------------
// MARK: - Observational Output (FACTS ONLY)
// ---------------------------------------------------------------------

struct PresenceObservation: Equatable {

    /// FAST9 / tracking confidence
    let confidence: Float

    /// Average spatial jitter over recent frames (px)
    let jitterPx: Double?

    /// Number of consecutive frames supporting presence
    let supportingFrames: Int

    /// Whether spatial occupancy evidence exists
    let spatialEvidencePresent: Bool
}

// ---------------------------------------------------------------------
// MARK: - Input
// ---------------------------------------------------------------------

struct PresenceObservationInput: Equatable {
    let timestampSec: Double
    let ballLockConfidence: Float
    let center: CGPoint?
    let speedPxPerSec: Double
    let spatialMask: Set<Int>?
}

// ---------------------------------------------------------------------
// MARK: - Observer
// ---------------------------------------------------------------------

final class PresenceAuthorityGate {

    // --------------------------------------------------
    // Tunables (OBSERVATIONAL ONLY)
    // --------------------------------------------------

    private let minConfidence: Float = 120
    private let maxJitterPx: Double = 4.0
    private let minStableFrames: Int = 6

    // --------------------------------------------------
    // State (ephemeral, non-authoritative)
    // --------------------------------------------------

    private var recentCenters: [CGPoint] = []

    private let staticAccumulator = StaticPresenceAccumulator()
    private let spatialObserver = SpatialPresenceObserver()

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------

    func reset() {
        recentCenters.removeAll()
        staticAccumulator.reset()
        spatialObserver.reset()
    }

    // --------------------------------------------------
    // Observe
    // --------------------------------------------------

    /// Observes presence-related evidence for this frame.
    /// Returns factual measurements only.
    func observe(_ input: PresenceObservationInput) -> PresenceObservation {

        var jitter: Double? = nil
        var supportingFrames = 0
        var spatialEvidence = false

        // --------------------------------------------------
        // Dynamic presence (FAST9 stability)
        // --------------------------------------------------

        if input.ballLockConfidence >= minConfidence,
           let center = input.center {

            recentCenters.append(center)
            if recentCenters.count > minStableFrames {
                recentCenters.removeFirst(recentCenters.count - minStableFrames)
            }

            if recentCenters.count >= minStableFrames {
                let avg = averagePoint(recentCenters)
                let maxDist = recentCenters
                    .map { hypot(Double($0.x - avg.x), Double($0.y - avg.y)) }
                    .max() ?? 0

                jitter = maxDist
                supportingFrames = recentCenters.count

                if maxDist <= maxJitterPx {
                    staticAccumulator.reset()
                    spatialObserver.reset()
                }
            }
        }

        // --------------------------------------------------
        // Static low-speed presence
        // --------------------------------------------------

        let staticResult = staticAccumulator.observe(
            center: input.center,
            speedPxPerSec: input.speedPxPerSec,
            presenceConfidence: input.ballLockConfidence
        )

        if case .stable(_, let frames) = staticResult {
            supportingFrames = max(supportingFrames, frames)
        }

        // --------------------------------------------------
        // Spatial occupancy
        // --------------------------------------------------

        let spatialResult = spatialObserver.observe(
            mask: input.spatialMask,
            confidence: input.ballLockConfidence
        )

        if case .present = spatialResult {
            spatialEvidence = true
        }

        // --------------------------------------------------
        // Emit OBSERVATION ONLY
        // --------------------------------------------------

        return PresenceObservation(
            confidence: input.ballLockConfidence,
            jitterPx: jitter,
            supportingFrames: supportingFrames,
            spatialEvidencePresent: spatialEvidence
        )
    }

    // --------------------------------------------------
    // Helpers
    // --------------------------------------------------

    private func averagePoint(_ pts: [CGPoint]) -> CGPoint {
        let sum = pts.reduce(CGPoint.zero) { acc, p in
            CGPoint(x: acc.x + p.x, y: acc.y + p.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(pts.count),
            y: sum.y / CGFloat(pts.count)
        )
    }
}
