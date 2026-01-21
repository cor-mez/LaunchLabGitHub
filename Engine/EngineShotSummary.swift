//
//  EngineShotSummary.swift
//  LaunchLab
//
//  Engine-level immutable shot summary (V1)
//
//  ROLE (STRICT):
//  - Represent ONLY authoritative outcomes emitted by ShotLifecycleController
//  - Contain no observational or intermediate metrics
//  - Safe for persistence, export, and UX display
//

import Foundation

struct EngineShotSummary {

    // ---------------------------------------------------------------------
    // MARK: - Identity
    // ---------------------------------------------------------------------

    let shotId: UUID

    // ---------------------------------------------------------------------
    // MARK: - Authoritative Timing
    // ---------------------------------------------------------------------

    let startTimestamp: Double
    let impactTimestamp: Double?
    let endTimestamp: Double

    // ---------------------------------------------------------------------
    // MARK: - Final Outcome
    // ---------------------------------------------------------------------

    /// True iff the shot was refused by the authority spine
    let refused: Bool

    /// Canonical refusal reason (if refused)
    /// Guaranteed to be explicit when refused == true
    let refusalReason: String?

    /// Final lifecycle state emitted by ShotLifecycleController
    /// (e.g. "shotFinalized", "refused")
    let finalState: String
}
