//
//  RSFrameObservation.swift
//  LaunchLab
//
//  Full-frame RS observability snapshot
//

import Foundation

struct RSFrameObservation {

    let timestamp: Double

    /// Aggregate (kept for continuity, NOT authority)
    let zmax: Float
    let dz: Float

    /// Per-row structure (critical)
    let rowProfiles: [RSRowProfile]

    /// Spatial coherence metrics
    let rowCorrelation: Float        // adjacent-row similarity
    let globalVariance: Float        // scene-wide change
    let localVariance: Float         // ROI-local change

    /// Diagnostics
    let droppedRows: Int
    let validRowCount: Int

    /// Explicit non-decision classification
    let classification: Classification

    enum Classification: String {
        case insufficientData
        case globalIlluminationChange
        case localizedShearCandidate
        case mixedSignal
        case unknown
    }
}
