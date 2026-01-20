//
//  StreakObservation.swift
//  LaunchLab
//
//  First-class observable for streak-based impact detection
//

import CoreGraphics

struct StreakObservation {

    // Core geometry
    let centroid: CGPoint
    let lengthPx: CGFloat
    let widthPx: CGFloat
    let orientationRad: CGFloat
    let rowSpan: Int

    // Coherence metrics
    let orientationVariance: CGFloat
    let localityRatio: CGFloat   // streak area / ROI area

    // Temporal
    let frameTimestamp: Double

    // Diagnostics
    let confidenceScore: CGFloat
    let rejectionReason: String?

    var isPhysicallyCoherent: Bool {
        rejectionReason == nil
    }
}
