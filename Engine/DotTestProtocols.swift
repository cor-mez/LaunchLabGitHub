//
//  DotTestProtocols.swift
//  LaunchLab
//
//  DotTest observability protocols (V1)
//
//  ROLE (STRICT):
//  - Provide OPTIONAL hooks for observability/debug layers
//  - NEVER surface shot detection, acceptance, or refusal
//  - NEVER reference Founder/UI telemetry models
//

import Foundation

/// Optional observer for DotTest observability events.
///
/// IMPORTANT:
/// - This protocol must remain authority-free.
/// - This protocol must not reference per-frame telemetry structs.
/// - This protocol must not reference shot records or summaries.
protocol DotTestObservabilityObserver: AnyObject {

    /// Called when a new frame has been processed by the DotTest pipeline.
    /// Intended for debug overlays or logging only.
    func didProcessDotTestFrame(at timestampSec: Double)
}

// MARK: - Default No-Op Implementation

extension DotTestObservabilityObserver {

    func didProcessDotTestFrame(at timestampSec: Double) {
        // Default no-op.
    }
}
