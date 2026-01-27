//
//  RSWindowAggregator.swift
//  LaunchLab
//
//  PHASE 3 — Temporal RS Envelope Aggregation (CONTRACT)
//
//  ROLE (STRICT):
//  - Define the Phase‑3 aggregation contract
//  - Describe WHAT a temporal RS window is
//  - Describe HOW it may be characterized
//  - NO authority
//  - NO shot decisions
//  - NO smoothing
//  - NO concrete implementation
//
//  This file is intentionally *stable* and should change rarely.
//  All physics interpretation happens downstream.
//

import Foundation

// ------------------------------------------------------------
// MARK: - Phase‑3 Window Outcome
// ------------------------------------------------------------

/// Descriptive characterization of a short RS time window.
/// These are observational labels, not acceptance decisions.
enum RSWindowOutcome: String {
    case insufficientData        // not enough frames to evaluate
    case noiseLike               // no coherent RS structure
    case structuredMotion        // coherent RS envelope present
}

// ------------------------------------------------------------
// MARK: - Phase‑3 Window Observation
// ------------------------------------------------------------

/// Immutable summary of a short RS time window.
/// Produced by a Phase‑3 aggregator and consumed by:
/// - offline analysis
/// - Phase‑4 gating
/// - future (non‑authoritative) reasoning layers
struct RSWindowObservation {

    // --------------------------------------------------------
    // Time bounds
    // --------------------------------------------------------

    /// Timestamp of first frame in window
    let startTime: Double

    /// Timestamp of last frame in window
    let endTime: Double

    /// Number of Phase‑2 frames contributing
    let frameCount: Int

    // --------------------------------------------------------
    // Envelope‑level observables
    // --------------------------------------------------------

    /// Maximum RS shear observed in window
    let zmaxPeak: Float

    /// Median RS shear across window
    let zmaxMedian: Float

    /// Number of frames exhibiting structured RS signal
    let structuredFrameCount: Int

    /// Fraction of frames classified as wide‑span
    let wideSpanFraction: Float

    // --------------------------------------------------------
    // Coherence metrics
    // --------------------------------------------------------

    /// Measures temporal continuity of RS signal (0–1)
    let temporalConsistency: Float

    /// Measures internal structural consistency of RS signal (0–1)
    let structureConsistency: Float

    // --------------------------------------------------------
    // Descriptive outcome
    // --------------------------------------------------------

    /// High‑level characterization of the window
    let outcome: RSWindowOutcome
}

// ------------------------------------------------------------
// MARK: - Phase‑3 Aggregator Contract
// ------------------------------------------------------------

/// Contract for Phase‑3 RS aggregation.
///
/// Implementations MUST:
/// - remain observability‑only
/// - ingest Phase‑2 frames without reinterpretation
/// - emit window‑level observations only
///
/// Implementations MUST NOT:
/// - smooth frames
/// - infer shot outcomes
/// - enforce product‑level thresholds
protocol RSPhase3Aggregating {

    /// Ingest a single Phase‑2 RS frame.
    /// Frames may be observable or refused.
    func ingest(_ frame: RSFrameObservation)

    /// Poll for a completed window observation.
    /// Returns nil if no window is ready.
    func poll() -> RSWindowObservation?

    /// Reset all internal state.
    func reset()
}
