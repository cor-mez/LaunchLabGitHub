//
//  BallLockV5.swift
//  LaunchLab
//
//  Blob-first ball lock.
//  OBSERVATIONAL ONLY — no authority.
//

import CoreGraphics

struct BallLockResult {
    let center: CGPoint
    let confidence: Float
}

final class BallLockV5 {

    // --------------------------------------------------
    // Tunables
    // --------------------------------------------------

    private let requiredStableFrames = 3
    private let maxCenterDrift: CGFloat = 12.0

    // --------------------------------------------------
    // State
    // --------------------------------------------------

    private var lastCenter: CGPoint?
    private var stableCount: Int = 0

    // --------------------------------------------------
    // Public API
    // --------------------------------------------------

    func update(blob: BlobSeed) -> BallLockResult? {

        defer { lastCenter = blob.center }

        if let last = lastCenter {
            let dx = blob.center.x - last.x
            let dy = blob.center.y - last.y
            let drift = hypot(dx, dy)

            if drift <= maxCenterDrift {
                stableCount += 1
            } else {
                stableCount = 0
                return nil
            }
        } else {
            stableCount = 1
        }

        guard stableCount >= requiredStableFrames else {
            return nil
        }

        return BallLockResult(
            center: blob.center,
            confidence: Float(blob.area)
        )
    }

    func reset() {
        lastCenter = nil
        stableCount = 0
    }
}
