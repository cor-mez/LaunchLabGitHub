//
//  DotTracker.swift
//  LaunchLab
//
//  Nearest-neighbor dot ID association.
//  - Preserves stable VisionDot.id values across frames
//  - Does NOT write velocity (VelocityTracker owns that)
//  - Returns updated DotTrackingState
//

import Foundation
import CoreGraphics

final class DotTracker {

    // Maximum distance (in pixels) to consider a detection
    // the same dot as a previous one.
    private let maxMatchDistance: CGFloat = 30.0
    private lazy var maxMatchDistanceSq: CGFloat = maxMatchDistance * maxMatchDistance

    // Next ID to give to a brand new dot.
    private var nextID: Int = 0

    // Optional external reset if you ever need to hard-reset IDs.
    func reset() {
        nextID = 0
    }

    // ---------------------------------------------------------------------
    // MARK: - Track
    // ---------------------------------------------------------------------
    /// Associate raw detection points with previous VisionDots.
    ///
    /// - Parameters:
    ///   - detections: raw 2D points from DotDetector (full-res pixel coords)
    ///   - previousDots: the dots from the previous frame
    ///   - previousState: previous tracking state
    ///
    /// - Returns:
    ///   - updatedDots: VisionDots with stable IDs (velocity = nil here)
    ///   - state: updated DotTrackingState
    ///
    func track(
        detections: [CGPoint],
        previousDots: [VisionDot],
        previousState: DotTrackingState
    ) -> ([VisionDot], DotTrackingState) {

        // No detections: we lost the pattern this frame.
        if detections.isEmpty {
            return ([], .lost)
        }

        // If no previous dots, bootstrap IDs.
        if previousDots.isEmpty {
            var result: [VisionDot] = []
            result.reserveCapacity(detections.count)

            for p in detections {
                let dot = VisionDot(
                    id: nextID,
                    position: p,
                    predicted: nil,
                    velocity: nil          // VelocityTracker will fill later
                )
                result.append(dot)
                nextID += 1
            }

            // First frame with detections → "initial"
            return (result, .initial)
        }

        // --------------------------------------------------------------
        // Nearest-neighbor association
        // --------------------------------------------------------------
        var updated: [VisionDot] = []
        updated.reserveCapacity(detections.count)

        var usedDetection = [Bool](repeating: false, count: detections.count)
        var matchedCount = 0

        // Match each previous dot to the nearest unused detection.
        for prev in previousDots {

            var bestIndex: Int? = nil
            var bestDistSq: CGFloat = .greatestFiniteMagnitude

            for (j, det) in detections.enumerated() where !usedDetection[j] {
                let dx = det.x - prev.position.x
                let dy = det.y - prev.position.y
                let d2 = dx*dx + dy*dy

                if d2 < bestDistSq {
                    bestDistSq = d2
                    bestIndex = j
                }
            }

            if let idx = bestIndex, bestDistSq <= maxMatchDistanceSq {
                // Matched: keep same ID, velocity left nil for VelocityTracker
                let det = detections[idx]

                let dot = VisionDot(
                    id: prev.id,
                    position: det,
                    predicted: nil,
                    velocity: nil      // VelocityTracker owns velocity
                )

                updated.append(dot)
                usedDetection[idx] = true
                matchedCount += 1

            } else {
                // No match within radius → drop this previous dot for now.
                continue
            }
        }

        // Create new dots for any unmatched detections.
        for (idx, det) in detections.enumerated() where !usedDetection[idx] {
            let dot = VisionDot(
                id: nextID,
                position: det,
                predicted: nil,
                velocity: nil
            )
            updated.append(dot)
            nextID += 1
        }

        // --------------------------------------------------------------
        // Tracking state update
        // --------------------------------------------------------------
        let state: DotTrackingState

        if matchedCount >= 4 {
            state = .tracking
        } else if matchedCount == 0 {
            state = .lost
        } else {
            // Transitional case: some matches but weak
            switch previousState {
            case .tracking:
                state = .tracking
            case .initial, .lost:
                state = .initial
            }
        }

        return (updated, state)
    }
}
