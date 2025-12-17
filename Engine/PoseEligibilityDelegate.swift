import CoreGraphics

/// Pure signaling contract.
/// No pose, no solver, no window access.
protocol PoseEligibilityDelegate: AnyObject {
    func ballLikeClusterDetected(
        center: CGPoint,
        radiusPx: CGFloat,
        confidence: Float,
        frameIndex: Int
    )
}

