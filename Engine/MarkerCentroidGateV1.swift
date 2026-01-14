//
//  MarkerCentroidGateV1.swift
//  LaunchLab
//
//  Centroid Motion Gate V1
//  Accepts motion only if centroid movement is:
//  - large enough
//  - directionally coherent
//  - temporally persistent
//

import CoreGraphics

final class MarkerCentroidGateV1 {

    // ---------------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    private let minDeltaPx: CGFloat = 1.5          // minimum per-frame movement
    private let maxDeltaPx: CGFloat = 40.0         // reject camera bumps
    private let minFrames: Int = 4                 // persistence window
    private let directionDotThreshold: CGFloat = 0.85 // ~30° cone

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    private var previousCenter: CGPoint?
    private var velocityHistory: [CGVector] = []

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        previousCenter = nil
        velocityHistory.removeAll()
    }

    // ---------------------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------------------

    /// Returns true only when coherent motion is observed.
    func update(center: CGPoint) -> Bool {

        guard let prev = previousCenter else {
            previousCenter = center
            return false
        }

        let dx = center.x - prev.x
        let dy = center.y - prev.y

        let mag = sqrt(dx * dx + dy * dy)

        previousCenter = center

        // -----------------------------------------------------------------
        // 1. Magnitude gate
        // -----------------------------------------------------------------

        guard mag >= minDeltaPx && mag <= maxDeltaPx else {
            velocityHistory.removeAll()
            return false
        }

        let v = CGVector(dx: dx / mag, dy: dy / mag)
        velocityHistory.append(v)

        if velocityHistory.count > minFrames {
            velocityHistory.removeFirst()
        }

        // -----------------------------------------------------------------
        // 2. Temporal persistence
        // -----------------------------------------------------------------

        guard velocityHistory.count >= minFrames else {
            return false
        }

        // -----------------------------------------------------------------
        // 3. Directional coherence
        // -----------------------------------------------------------------

        let ref = velocityHistory.first!

        for u in velocityHistory.dropFirst() {
            let dot = ref.dx * u.dx + ref.dy * u.dy
            if dot < directionDotThreshold {
                velocityHistory.removeAll()
                return false
            }
        }

        return true
    }
}
