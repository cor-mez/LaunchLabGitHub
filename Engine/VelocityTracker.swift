// VelocityTracker.swift
// Stateless externally; internal state across frames.

import Foundation
import CoreGraphics
import CoreVideo
import simd

/// Per-dot history used by VelocityTracker
private struct VelocityDotState {
    var lastPosition: CGPoint
    var lastTimestamp: Double
}

public final class VelocityTracker {

    // MARK: - Configuration

    /// Max time gap we treat as “continuous” (seconds). Larger gaps reset prediction.
    private let maxContinuousDeltaTime: Double = 1.0 / 30.0 // ~33 ms

    // MARK: - State

    private var dotStates: [Int: VelocityDotState] = [:]
    private var lastTimestamp: Double?
    private var lastPixelBuffer: CVPixelBuffer?

    // MARK: - Public API

    /// Call once per frame AFTER DotTracker + PoseSolver.
    ///
    /// - Parameters:
    ///   - dots: Tracked dots for the current frame (with stable IDs).
    ///   - pixelBuffer: Current frame buffer (stored for future LK use).
    ///   - timestamp: Current frame timestamp in seconds.
    ///
    /// - Returns: Updated dots with `flow` and `predicted` filled where possible.
    public func process(
        dots: [VisionDot],
        pixelBuffer: CVPixelBuffer,
        timestamp: Double
    ) -> [VisionDot] {

        let previousTimestamp = lastTimestamp
        let dtRaw = timestamp - (previousTimestamp ?? timestamp)
        let dt = dtRaw > 0 ? dtRaw : 0

        var updatedDots: [VisionDot] = []
        updatedDots.reserveCapacity(dots.count)

        // If we don’t have previous data or dt is too large, treat as reset.
        let shouldReset = previousTimestamp == nil || dt <= 0 || dt > maxContinuousDeltaTime

        for var dot in dots {
            guard !shouldReset,
                  let state = dotStates[dot.id] else {
                // No valid history for this dot
                dot.flow = nil
                dot.predicted = nil
                updatedDots.append(dot)
                continue
            }

            // Compute pixel displacement from last known position.
            let dx = Float(dot.position.x - state.lastPosition.x)
            let dy = Float(dot.position.y - state.lastPosition.y)
            let flow = SIMD2<Float>(dx, dy)
            dot.flow = flow

            // Constant-velocity prediction for next frame:
            // Predict position after another dt (same interval).
            let nextX = dot.position.x + CGFloat(dx)
            let nextY = dot.position.y + CGFloat(dy)
            dot.predicted = CGPoint(x: nextX, y: nextY)

            updatedDots.append(dot)
        }

        // Update internal state for next frame
        lastTimestamp = timestamp
        lastPixelBuffer = pixelBuffer
        dotStates.removeAll(keepingCapacity: true)
        for dot in updatedDots {
            dotStates[dot.id] = VelocityDotState(
                lastPosition: dot.position,
                lastTimestamp: timestamp
            )
        }

        return updatedDots
    }

    /// Reset all internal history, e.g. on capture restart or resolution change.
    public func reset() {
        dotStates.removeAll()
        lastTimestamp = nil
        lastPixelBuffer = nil
    }
}
