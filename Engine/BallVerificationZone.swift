//
//  BallVerificationZone.swift
//  LaunchLab
//
//  Defines the ONLY spatial + temporal region
//  where post-impulse evidence may confirm a shot.
//

import CoreGraphics

struct BallVerificationZone {

    // -------------------------------------------------------------
    // MARK: - Geometry (LOCKED FOR V1)
    // -------------------------------------------------------------

    /// Relative depth from impact (in screen space).
    /// Ball must appear here shortly after impulse.
    static let minYRatio: CGFloat = 0.35
    static let maxYRatio: CGFloat = 0.65

    /// Horizontal tolerance around impact line.
    static let maxXDeviationPx: CGFloat = 80.0

    // -------------------------------------------------------------
    // MARK: - Temporal Constraints
    // -------------------------------------------------------------

    /// Ball must emerge quickly after impulse.
    static let maxEmergenceDelayMs: Double = 35.0

    // -------------------------------------------------------------
    // MARK: - Verification
    // -------------------------------------------------------------

    static func contains(
        point: CGPoint,
        frameSize: CGSize,
        impactX: CGFloat
    ) -> Bool {

        let yRatio = point.y / frameSize.height
        let xDelta = abs(point.x - impactX)

        return
            yRatio >= minYRatio &&
            yRatio <= maxYRatio &&
            xDelta <= maxXDeviationPx
    }
}
