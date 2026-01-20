//
//  FounderTelemetryObserver.swift
//  LaunchLab
//
//  Engine → App telemetry boundary (V1)
//
//  ROLE (STRICT):
//  - Surface AUTHORITATIVE engine outputs only
//  - Never surface observational or inferred telemetry
//  - Never imply shot detection or completion unless emitted by authority
//

import Foundation

/// Read-only observer for authoritative engine events.
///
/// IMPORTANT:
/// - This protocol must NOT reference observational telemetry
/// - This protocol must NOT reference ShotRecord or per-frame data
/// - All data here is produced by ShotLifecycleController
protocol FounderTelemetryObserver: AnyObject {

    /// Called ONLY when the authority spine emits a finalized shot summary.
    /// May never be called in refusal-only mode.
    func didEmitAuthoritativeShot(
        _ summary: EngineShotSummary,
        allSummaries: [EngineShotSummary]
    )
}

// MARK: - Default No-Op Implementation

extension FounderTelemetryObserver {

    func didEmitAuthoritativeShot(
        _ summary: EngineShotSummary,
        allSummaries: [EngineShotSummary]
    ) {
        // Default no-op.
        // Conformers may safely ignore authoritative emissions.
    }
}
