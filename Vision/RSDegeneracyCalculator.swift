// File: Vision/RS/RSDegeneracyCalculator.swift
//
//  RSDegeneracyCalculator.swift
//  LaunchLab
//
//  Rolling-shutter degeneracy metrics + confidence gating.
//  Enforces RS-PnP safety based on camera placement and image geometry.
//

import Foundation
import CoreGraphics
import simd

/// Raw per-frame metrics used to decide RS suitability.
struct RSDegeneracyInput {
    /// Approx horizontal shear in px / row (absolute value).
    var shearSlope: CGFloat
    /// Vertical span of the ball pattern in pixels (e.g. image diameter).
    var rowSpanPx: CGFloat
    /// Estimated motion / exposure blur streak length in pixels.
    var blurStreakPx: CGFloat
    /// Dimensionless phase ratio derived from 72-dot tracking.
    var phaseRatio: CGFloat
    /// Ball size in pixels (radius in image space).
    var ballPx: CGFloat
    /// True if the capture device is in portrait orientation.
    var isPortrait: Bool
}

/// Final degeneracy decision for the current frame.
struct RSDegeneracyResult {
    let shearSlope: CGFloat
    let rowSpanPx: CGFloat
    let blurStreakPx: CGFloat
    let phaseRatio: CGFloat
    let ballPx: CGFloat

    /// True when RS-PnP must be disabled for this frame / shot.
    let criticalDegeneracy: Bool
    /// 0–1 confidence that RS-PnP will be numerically stable.
    let rsConfidence: CGFloat
}

/// Simple placement hint for pre-shot "waggle test".
struct WagglePlacementHint {
    let isValid: Bool
    let shearSlope: CGFloat
    let message: String
}

struct RSDegeneracyCalculator {

    // MARK: - Public API

    func evaluate(_ input: RSDegeneracyInput) -> RSDegeneracyResult {
        // Critical thresholds (hard blocks).
        let critShearThreshold: CGFloat = 0.10      // px / row
        let critRowSpanThreshold: CGFloat = 30.0    // px
        let critBlurThreshold: CGFloat = 3.0        // px
        let critBallPxThreshold: CGFloat = 15.0     // px radius

        // Soft thresholds (confidence penalties).
        let softShearThreshold: CGFloat = 0.15      // px / row
        let softRowSpanThreshold: CGFloat = 40.0    // px
        let softBlurThreshold: CGFloat = 2.0        // px
        let softBallPxThreshold: CGFloat = 20.0     // px radius
        let phaseAliasThreshold: CGFloat = 1.6      // dimensionless

        var critical = false
        var nonCriticalPenaltyCount = 0

        // Portrait-orientation requirement.
        if !input.isPortrait {
            critical = true
        }

        // Shear slope.
        if input.shearSlope < critShearThreshold {
            critical = true
        } else if input.shearSlope < softShearThreshold {
            nonCriticalPenaltyCount += 1
        }

        // Row-span.
        if input.rowSpanPx < critRowSpanThreshold {
            critical = true
        } else if input.rowSpanPx < softRowSpanThreshold {
            nonCriticalPenaltyCount += 1
        }

        // Blur streak.
        if input.blurStreakPx > critBlurThreshold {
            critical = true
        } else if input.blurStreakPx > softBlurThreshold {
            nonCriticalPenaltyCount += 1
        }

        // Ball image size.
        if input.ballPx < critBallPxThreshold {
            critical = true
        } else if input.ballPx < softBallPxThreshold {
            nonCriticalPenaltyCount += 1
        }

        // Phase ratio (non-critical aliasing hint only for now).
        if input.phaseRatio > phaseAliasThreshold {
            nonCriticalPenaltyCount += 1
        }

        // Confidence scoring.
        let confidence: CGFloat
        if critical {
            confidence = 0.0
        } else {
            // 1.0 − 0.18 per non-critical penalty, clamped into [0, 1].
            let penaltyPerFlag: CGFloat = 0.18
            let raw = 1.0 - penaltyPerFlag * CGFloat(nonCriticalPenaltyCount)
            confidence = max(0.0, min(1.0, raw))
        }

        return RSDegeneracyResult(
            shearSlope: input.shearSlope,
            rowSpanPx: input.rowSpanPx,
            blurStreakPx: input.blurStreakPx,
            phaseRatio: input.phaseRatio,
            ballPx: input.ballPx,
            criticalDegeneracy: critical,
            rsConfidence: confidence
        )
    }

    /// Lightweight shear-slope estimator from local LK flow around the ball.
    ///
    /// - Parameters:
    ///   - dots: All LK-refined dots for the frame.
    ///   - flows: Matched LK flow vectors (same ordering as `dots`).
    ///   - roiCenter: Center of ball/club ROI in pixels.
    ///   - roiRadius: ROI radius in pixels.
    /// - Returns: Absolute shear slope in px / row.
    func estimateShearSlope(
        dots: [VisionDot],
        flows: [SIMD2<Float>],
        roiCenter: CGPoint,
        roiRadius: CGFloat
    ) -> CGFloat {
        let count = min(dots.count, flows.count)
        guard count > 1 else { return 0.0 }

        let radiusSq = roiRadius * roiRadius
        var ys: [CGFloat] = []
        var dxs: [CGFloat] = []

        ys.reserveCapacity(count)
        dxs.reserveCapacity(count)

        for i in 0..<count {
            let dot = dots[i]
            let flow = flows[i]

            let pos = dot.position
            let dxPos = pos.x - roiCenter.x
            let dyPos = pos.y - roiCenter.y
            let distSq = dxPos * dxPos + dyPos * dyPos
            if distSq > radiusSq {
                continue
            }

            let dx = CGFloat(flow.x)
            let dy = CGFloat(flow.y)
            let magSq = dx * dx + dy * dy
            if magSq < 0.01 {
                continue // ignore tiny/noisy flows
            }

            ys.append(pos.y)
            dxs.append(dx)
        }

        let n = ys.count
        guard n > 1 else { return 0.0 }

        let meanY = ys.reduce(0, +) / CGFloat(n)
        let meanDx = dxs.reduce(0, +) / CGFloat(n)

        var num: CGFloat = 0.0
        var den: CGFloat = 0.0
        for i in 0..<n {
            let dy = ys[i] - meanY
            let ddx = dxs[i] - meanDx
            num += dy * ddx
            den += dy * dy
        }

        guard den > 1e-4 else { return 0.0 }
        let slope = num / den // dx per 1 px in y
        return abs(slope)
    }

    /// Waggle placement helper. Call this while the user performs a slow
    /// practice swing to validate the camera roll / orientation.
    ///
    /// If `shearSlope < 0.10` the setup is considered degenerate and the
    /// user should be instructed to increase roll tilt and maintain portrait.
    func waggleHint(for shearSlope: CGFloat) -> WagglePlacementHint {
        let threshold: CGFloat = 0.10
        if shearSlope < threshold {
            return WagglePlacementHint(
                isValid: false,
                shearSlope: shearSlope,
                message: "Camera tilt too flat for RS solve. Increase roll tilt (10–15°) and keep the phone in portrait behind and slightly inside the ball."
            )
        } else {
            return WagglePlacementHint(
                isValid: true,
                shearSlope: shearSlope,
                message: "Camera placement looks OK for RS solve."
            )
        }
    }
}