//
//  RefusalReason.swift
//  LaunchLab
//
//  Enumerates all refusal causes.
//  Refusals are final, truthful outcomes.
//

enum RefusalReason {

    // -----------------------------------------------------------------
    // MARK: - Signal / Detection Refusals
    // -----------------------------------------------------------------

    case insufficientConfidence
    case insufficientMotion
    case markerLost
    case ambiguousDetection

    // -----------------------------------------------------------------
    // MARK: - Lifecycle / Mechanical Refusals
    // -----------------------------------------------------------------

    /// Lifecycle exceeded maximum allowed duration
    /// (deadman absolute timeout)
    case lifecycleTimeout

    /// Impact observed but no valid separation within time window
    /// (occlusion, ROI exit, skipped phase)
    case postImpactTimeout
}
