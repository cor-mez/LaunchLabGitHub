//
//  RSObservabilityClassifier.swift
//  LaunchLab
//
//  Pure classification of RS observability.
//  No temporal state. No authority.
//

import Foundation

struct RSObservabilityClassifier {

    static func classify(
        zmax: Float,
        dz: Float,
        rowCorrelation: Float,
        globalVariance: Float,
        localVariance: Float,
        validRowCount: Int,
        centroid: CGPoint?
    ) -> RSFrameClassification {

        // -----------------------------------------------------
        // Hard integrity failures
        // -----------------------------------------------------

        if validRowCount < 8 {
            return .refused(.insufficientRowSupport)
        }

        // -----------------------------------------------------
        // Global RS dominance (flicker)
        // -----------------------------------------------------

        if rowCorrelation > 0.85 && globalVariance > localVariance {
            return .refused(.flickerAligned)
        }

        // -----------------------------------------------------
        // Locality breakdown
        // -----------------------------------------------------

        if centroid == nil {
            return .refused(.localityUnstable)
        }

        // -----------------------------------------------------
        // Ambiguous impulse
        // -----------------------------------------------------

        if dz > 0 && zmax > 0 {
            return .refused(.impulseAmbiguous)
        }

        // -----------------------------------------------------
        // Observable (not accepted)
        // -----------------------------------------------------

        return .observable
    }
}
