//
//  SeparationAuthorityGate.swift
//  LaunchLab
//
//  Separation Observability Module (V1)
//
//  ROLE (STRICT):
//  - Measure post-impact ballistic separation characteristics
//  - Produce observational evidence only
//  - NEVER authorize, confirm, or finalize a shot
//

import Foundation
import CoreGraphics

/// Observational separation evidence.
/// Carries structured facts across multiple frames.
struct SeparationEvidence {

    let framesObserved: Int
    let speedPxPerSec: Double
    let escapeDistancePx: Double
    let directionDot: Double
    let cameraStable: Bool
}

/// Stateless separation observer.
/// All state is per-attempt and reset externally.
final class SeparationAuthorityGate {

    // MARK: - Conservative V1 thresholds (OBSERVATIONAL)

    private let minFrames: Int = 3
    private let minSpeedPxPerSec: Double = 30.0
    private let minEscapePx: Double = 6.0
    private let maxDirectionFlipDot: Double = 0.6

    // MARK: - State (OBSERVATIONAL ONLY)

    private var frames: Int = 0
    private var origin: CGPoint?
    private var lastDir: CGVector?

    // MARK: - Reset

    func reset() {
        frames = 0
        origin = nil
        lastDir = nil
    }

    // MARK: - Update

    /// Observe separation characteristics for the current frame.
    /// Returns SeparationEvidence when minimum structure exists,
    /// otherwise returns nil.
    func observe(
        center: CGPoint,
        velocityPx: CGVector,
        speedPxPerSec: Double,
        cameraStable: Bool
    ) -> SeparationEvidence? {

        // Camera stability is observed, not enforced
        if !cameraStable {
            Log.info(.shot, "[OBSERVE] separation camera_unstable")
            reset()
            return nil
        }

        // Speed gate (observational)
        guard speedPxPerSec >= minSpeedPxPerSec else {
            Log.info(
                .shot,
                "[OBSERVE] separation below_min_speed px_s=\(fmt1(speedPxPerSec))"
            )
            reset()
            return nil
        }

        let dir = normalize(velocityPx)

        // First-frame initialization
        if origin == nil {
            origin = center
            lastDir = dir
            frames = 1
            return nil
        }

        frames += 1

        // Direction coherence
        let dot: Double
        if let last = lastDir {
            dot = Double((dir.dx * last.dx) + (dir.dy * last.dy))
            if dot < maxDirectionFlipDot {
                Log.info(
                    .shot,
                    "[OBSERVE] separation direction_flip dot=\(fmt2(dot))"
                )
                reset()
                return nil
            }
        } else {
            dot = 1.0
        }

        // Spatial escape
        let dx = center.x - origin!.x
        let dy = center.y - origin!.y
        let dist = hypot(dx, dy)

        guard dist >= minEscapePx else {
            Log.info(
                .shot,
                "[OBSERVE] separation insufficient_escape dist=\(fmt2(dist))"
            )
            return nil
        }

        lastDir = dir

        // Frame accumulation
        guard frames >= minFrames else {
            Log.info(
                .shot,
                "[OBSERVE] separation insufficient_frames frames=\(frames)"
            )
            return nil
        }

        // --------------------------------------------------
        // OBSERVATIONAL OUTPUT (NO AUTHORITY)
        // --------------------------------------------------

        Log.info(
            .shot,
            "[OBSERVE] separation frames=\(frames) px_s=\(fmt1(speedPxPerSec)) dist=\(fmt2(dist))"
        )

        return SeparationEvidence(
            framesObserved: frames,
            speedPxPerSec: speedPxPerSec,
            escapeDistancePx: dist,
            directionDot: dot,
            cameraStable: cameraStable
        )
    }

    // MARK: - Helpers

    private func normalize(_ v: CGVector) -> CGVector {
        let mag = hypot(v.dx, v.dy)
        guard mag > 1e-6 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func fmt2(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
