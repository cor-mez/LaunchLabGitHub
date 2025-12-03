// File: Engine/DotTracker.swift
// LaunchLab
//
// Nearest-neighbor dot ID association.
// Preserves FAST9 score across frames when matching.
// Assigns score=0 for new dots (VelocityTracker fills velocity later).
//

import Foundation
import CoreGraphics

final class DotTracker {

    // Maximum distance (in pixels) to consider a detection
    // the same dot as a previous one.
    private let maxMatchDistance: CGFloat = 30.0
    private lazy var maxMatchDistanceSq: CGFloat = maxMatchDistance * maxMatchDistance

    private var nextID: Int = 0

    func reset() {
        nextID = 0
    }

    // ---------------------------------------------------------------------
    // MARK: - Track
    // ---------------------------------------------------------------------
    func track(
        detections: [CGPoint],
        previousDots: [VisionDot],
        previousState: DotTrackingState
    ) -> ([VisionDot], DotTrackingState) {

        // --------------------------------------------------------------
        // Case 1: No detections → lost state
        // --------------------------------------------------------------
        if detections.isEmpty {
            return ([], .lost)
        }

        // --------------------------------------------------------------
        // Case 2: No previous dots → bootstrap IDs
        // --------------------------------------------------------------
        if previousDots.isEmpty {
            var result: [VisionDot] = []
            result.reserveCapacity(detections.count)

            for p in detections {
                let dot = VisionDot(
                    id: nextID,
                    position: p,
                    score: 0.0,            // NEW DOT → score = 0
                    predicted: nil,
                    velocity: nil
                )
                result.append(dot)
                nextID += 1
            }
            return (result, .initial)
        }

        // --------------------------------------------------------------
        // Case 3: Nearest-neighbor association
        // --------------------------------------------------------------
        var updated: [VisionDot] = []
        updated.reserveCapacity(detections.count)

        var usedDetection = Array(repeating: false, count: detections.count)
        var matchedCount = 0

        // Try matching previous dots
        for prev in previousDots {

            var bestIndex: Int? = nil
            var bestDistSq: CGFloat = .greatestFiniteMagnitude

            for (j, det) in detections.enumerated() where !usedDetection[j] {
                let dx = det.x - prev.position.x
                let dy = det.y - prev.position.y
                let dist2 = dx*dx + dy*dy

                if dist2 < bestDistSq {
                    bestDistSq = dist2
                    bestIndex = j
                }
            }

            if let idx = bestIndex, bestDistSq <= maxMatchDistanceSq {

                let det = detections[idx]

                let dot = VisionDot(
                    id: prev.id,
                    position: det,
                    score: prev.score,         // PRESERVE SCORE
                    predicted: prev.predicted,
                    velocity: nil              // VelocityTracker handles velocity
                )

                updated.append(dot)
                usedDetection[idx] = true
                matchedCount += 1

            } else {
                continue
            }
        }

        // --------------------------------------------------------------
        // Add new dots (unmatched detections)
        // --------------------------------------------------------------
        for (idx, det) in detections.enumerated() where !usedDetection[idx] {

            let dot = VisionDot(
                id: nextID,
                position: det,
                score: 0.0,          // NEW dot → zero score
                predicted: nil,
                velocity: nil
            )

            updated.append(dot)
            nextID += 1
        }

        // --------------------------------------------------------------
        // Tracking state transitions
        // --------------------------------------------------------------
        let state: DotTrackingState

        if matchedCount >= 4 {
            state = .tracking
        } else if matchedCount == 0 {
            state = .lost
        } else {
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
