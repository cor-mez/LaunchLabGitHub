//
//  ShotLock.swift
//  LaunchLab
//
//  Shot Lock Observability (V1)
//
//  ROLE (STRICT):
//  - Capture per-frame impulse evidence
//  - NEVER latch, block, or enforce single-shot behavior
//  - Authority lives exclusively in ShotLifecycleController
//

import Foundation

/// Observational impulse snapshot.
/// Carries facts only.
struct ShotLockObservation {

    let timestamp: Double
    let zMax: Float
}

/// Stateless helper for packaging impulse evidence.
/// Does NOT enforce locking or exclusivity.
enum ShotLock {

    /// Package impulse evidence for the current frame.
    /// Caller decides whether and how to use it.
    static func observe(
        timestamp: Double,
        zMax: Float
    ) -> ShotLockObservation {

        ShotLockObservation(
            timestamp: timestamp,
            zMax: zMax
        )
    }
}
