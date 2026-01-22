//
//  RSRefusalReason.swift
//  LaunchLab
//
//  Canonical refusal taxonomy for RS observability.
//  Naming epistemic failure modes — not detection outcomes.
//

import Foundation

enum RSRefusalReason: UInt16, CaseIterable {

    // ---------------------------------------------------------
    // Global RS dominance (lighting / ISP driven)
    // ---------------------------------------------------------

    /// Rolling shutter artifacts are globally aligned across the frame,
    /// consistent with flicker or ISP-induced luma modulation.
    case flickerAligned = 100

    /// Row correlation is high across most of the frame,
    /// indicating non-localized RS effects.
    case globalRowCorrelation

    // ---------------------------------------------------------
    // Locality breakdown
    // ---------------------------------------------------------

    /// RS energy detected, but spatial locality cannot be anchored.
    /// (No stable centroid or envelope.)
    case localityUnstable

    /// Local RS signal exists but is underconstrained by geometry.
    case geometryUnderconstrained

    // ---------------------------------------------------------
    // Ambiguous impulse
    // ---------------------------------------------------------

    /// Δz impulse present, but indistinguishable from a fast shadow
    /// or club-only motion under current constraints.
    case impulseAmbiguous

    // ---------------------------------------------------------
    // Data integrity
    // ---------------------------------------------------------

    /// Insufficient valid rows after masking / rejection.
    case insufficientRowSupport

    /// Frame dropped or RS readout incomplete.
    case frameIntegrityFailure

    // ---------------------------------------------------------
    // Structural guard (must never be emitted implicitly)
    // ---------------------------------------------------------

    /// Reserved refusal for defensive completeness.
    /// Should only be used if classification invariants are violated.
    case classificationInvariantViolation
}
