//
//  RSFrameObservation.swift
//  LaunchLab
//
//  Immutable RS observability snapshot for a single frame.
//
//  CONTRACT:
//  - Every frame MUST terminate in exactly one RSObservationOutcome
//  - No partial, pending, or unknown states
//  - Contains raw observables only (no authority, no inference)
//

import Foundation
import CoreGraphics

struct RSFrameObservation: Equatable {

    // ---------------------------------------------------------
    // MARK: - Timing
    // ---------------------------------------------------------

    /// Presentation timestamp (seconds, monotonic)
    let timestamp: Double

    // ---------------------------------------------------------
    // MARK: - RS metrics (raw, unfiltered)
    // ---------------------------------------------------------

    /// Maximum rolling-shutter shear magnitude
    let zmax: Float

    /// Instantaneous shear gradient (Δz)
    let dz: Float

    /// Correlation of RS effects across rows (global sensitivity)
    let rowCorrelation: Float

    /// Global luma variance (frame-wide)
    let globalVariance: Float

    /// Local luma variance (ROI / centroid-local)
    let localVariance: Float

    /// Number of valid rows contributing to RS estimation
    let validRowCount: Int

    /// Rows discarded due to masking / integrity checks
    let droppedRows: Int

    // ---------------------------------------------------------
    // MARK: - Spatial anchoring
    // ---------------------------------------------------------

    /// Local centroid of RS activity (if anchorable)
    let centroid: CGPoint?

    /// Radius of the localized RS envelope (if defined)
    let envelopeRadius: Float?

    // ---------------------------------------------------------
    // MARK: - Mandatory Outcome
    // ---------------------------------------------------------

    /// Final epistemic outcome for this frame.
    /// MUST be either:
    ///   - .observable
    ///   - .refused(reason)
    let outcome: RSObservationOutcome
}

// MARK: - Convenience (NON-AUTHORITATIVE)

extension RSFrameObservation {

    /// True iff this frame is usable for RS analysis.
    @inline(__always)
    var isObservable: Bool {
        outcome.isObservable
    }

    /// Refusal reason, if the frame is epistemically undecidable.
    @inline(__always)
    var refusalReason: RSRefusalReason? {
        outcome.refusalReason
    }
}
