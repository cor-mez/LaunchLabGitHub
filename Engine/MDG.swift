//MDG.swift

import Foundation
import CoreGraphics
struct MDGDecision {
    let ballLikeEvidence: Bool
    let reason: String?
}

final class MarkerlessDiscriminationGate {

    // MARK: - Internal state (MDG-owned)
    private var lastCenter: CGPoint?
    private var lastFrameIndex: Int?

    func evaluate(
        points: [CGPoint],
        candidateCenter: CGPoint,
        candidateRadiusPx: CGFloat,
        frameIndex: Int
    ) -> MDGDecision {

        defer {
            lastCenter = candidateCenter
            lastFrameIndex = frameIndex
        }

        // ----------------------------
        // Motion plausibility (frame-based)
        // ----------------------------
        if let prevCenter = lastCenter,
           let prevFrame = lastFrameIndex {

            let df = max(frameIndex - prevFrame, 1)
            let dx = candidateCenter.x - prevCenter.x
            let dy = candidateCenter.y - prevCenter.y
            let motionPxPerFrame = hypot(dx, dy) / CGFloat(df)

            if motionPxPerFrame < 0.05 {
                if DebugProbe.isEnabled(.capture) {
                    Log.info(.detection, "MDG MOTION reject static v=\(motionPxPerFrame)")
                }
                return MDGDecision(
                    ballLikeEvidence: false,
                    reason: "static_motion"
                )
            }
        }

        // ----------------------------
        // Geometric gate placeholder (next step)
        // ----------------------------
        if DebugProbe.isEnabled(.capture) {
            Log.info(.detection, "MDG GEOM accept placeholder")
        }

        return MDGDecision(
            ballLikeEvidence: true,
            reason: nil
        )
    }
}
