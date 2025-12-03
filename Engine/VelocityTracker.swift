//
//  VelocityTracker.swift
//  LaunchLab
//
//  Computes per-dot velocity between frames.
//  Here: simple frame-to-frame displacement (no /dt),
//  so overlay has clear, visible arrows.
//
//  - velocity = nil if no previous position
//  - no smoothing
//  - IDs preserved
//

import Foundation
import CoreGraphics

public final class VelocityTracker {

    // Last known dot positions keyed by ID
    private var lastPositions: [Int: CGPoint] = [:]

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------
    public func update(
        previousDots: [VisionDot],
        currentDots: [VisionDot],
        dt: Double
    ) -> [VisionDot] {

        // Build the previous-position map
        lastPositions.removeAll(keepingCapacity: true)
        for dot in previousDots {
            lastPositions[dot.id] = dot.position
        }

        var output: [VisionDot] = []
        output.reserveCapacity(currentDots.count)

        for dot in currentDots {

            if let prevPos = lastPositions[dot.id] {

                let dx = dot.position.x - prevPos.x
                let dy = dot.position.y - prevPos.y

                let v = CGVector(dx: dx, dy: dy)

                output.append(
                    VisionDot(
                        id: dot.id,
                        position: dot.position,
                        score: dot.score,        // ← FIX
                        predicted: dot.predicted,
                        velocity: v
                    )
                )

            } else {

                output.append(
                    VisionDot(
                        id: dot.id,
                        position: dot.position,
                        score: dot.score,         // ← FIX
                        predicted: dot.predicted,
                        velocity: nil
                    )
                )
            }
        }

        return output
    }
}
