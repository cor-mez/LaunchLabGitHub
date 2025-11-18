import Foundation
import CoreGraphics

/// Lightweight per-dot velocity smoother.
/// Name is KalmanFilter, but implementation is a tuned exponential smoother
/// over raw (PyrLK-based) velocity measurements.
final class VelocityKalmanFilter {

    private struct State {
        var position: CGPoint
        var velocity: CGVector
        var timestamp: Double
    }

    // Keyed by VisionDot.id
    private var states: [Int: State] = [:]

    /// Weight of the latest measurement vs. previous estimate (0–1).
    /// Higher = more responsive, lower = smoother.
    var measurementGain: CGFloat = 0.35

    func reset() {
        states.removeAll()
    }

    /// Update / create a smoothed velocity estimate for a given dot.
    ///
    /// - Parameters:
    ///   - dotID: Stable VisionDot.id
    ///   - position: Current pixel-space position
    ///   - rawVelocity: Raw px/sec measurement (from PyrLK or fallback)
    ///   - timestamp: Current frame timestamp in seconds
    ///
    /// - Returns: Smoothed velocity vector in px/sec.
    func update(
        dotID: Int,
        position: CGPoint,
        rawVelocity: CGVector,
        timestamp: Double
    ) -> CGVector {
        let alpha = measurementGain.clamped(to: 0.0 ... 1.0)

        if var state = states[dotID] {
            // Blend new measurement with previous estimate
            let blended = CGVector(
                dx: alpha * rawVelocity.dx + (1.0 - alpha) * state.velocity.dx,
                dy: alpha * rawVelocity.dy + (1.0 - alpha) * state.velocity.dy
            )

            state.position = position
            state.velocity = blended
            state.timestamp = timestamp
            states[dotID] = state
            return blended
        } else {
            let initial = rawVelocity
            let newState = State(position: position, velocity: initial, timestamp: timestamp)
            states[dotID] = newState
            return initial
        }
    }
}

// MARK: - Small helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
