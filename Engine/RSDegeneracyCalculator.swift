// File: Vision/RS/RSDegeneracyCalculator.swift
//
//  RSDegeneracyCalculator.swift
//  LaunchLab
//
//  Rolling-shutter degeneracy + flicker-aware confidence.
//

import Foundation
import CoreGraphics
import simd

/// Raw per-frame metrics used to decide RS suitability.
struct RSDegeneracyInput {
    var shearSlope: CGFloat
    var rowSpanPx: CGFloat
    var blurStreakPx: CGFloat
    var phaseRatio: CGFloat
    var ballPx: CGFloat
    var isPortrait: Bool
    var flickerModulation: CGFloat
}

/// Final degeneracy decision for the current frame.
struct RSDegeneracyResult {
    let shearSlope: CGFloat
    let rowSpanPx: CGFloat
    let blurStreakPx: CGFloat
    let phaseRatio: CGFloat
    let ballPx: CGFloat
    let flickerModulation: CGFloat

    let criticalDegeneracy: Bool
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

    func evaluate(
        _ input: RSDegeneracyInput,
        isFlickerUnsafe: Bool
    ) -> RSDegeneracyResult {

        // Critical thresholds (hard blocks).
        let critShearThreshold: CGFloat = 0.10      // px / row
        let critRowSpanThreshold: CGFloat = 30.0    // px
        let critBlurThreshold: CGFloat = 3.0        // px
        let critBallPxThreshold: CGFloat = 15.0     // px

        // Soft thresholds (confidence penalties).
        let softShearThreshold: CGFloat = 0.15      // px / row
        let softRowSpanThreshold: CGFloat = 40.0    // px
        let softBlurThreshold: CGFloat = 2.0        // px
        let softBallPxThreshold: CGFloat = 20.0     // px
        let phaseAliasThreshold: CGFloat = 1.6      // dimensionless

        var critical = false
        var confidence: CGFloat = 1.0

        // Portrait-orientation requirement.
        if !input.isPortrait {
            critical = true
        }

        // Shear slope.
        if input.shearSlope < critShearThreshold {
            critical = true
        } else if input.shearSlope < softShearThreshold {
            confidence -= 0.18
        }

        // Row-span.
        if input.rowSpanPx < critRowSpanThreshold {
            critical = true
        } else if input.rowSpanPx < softRowSpanThreshold {
            confidence -= 0.18
        }

        // Blur streak.
        if input.blurStreakPx > critBlurThreshold {
            critical = true
        } else if input.blurStreakPx > softBlurThreshold {
            confidence -= 0.15
        }

        // Ball image size.
        if input.ballPx < critBallPxThreshold {
            critical = true
        } else if input.ballPx < softBallPxThreshold {
            confidence -= 0.18
        }

        // Phase ratio (non-critical aliasing hint).
        if input.phaseRatio > phaseAliasThreshold {
            confidence -= 0.15
        }

        // Flicker modulation penalty (0.25–0.40).
        if input.flickerModulation > 0.15 {
            confidence -= 0.3
        }

        // Flicker-unsafe frames: force critical.
        if isFlickerUnsafe {
            critical = true
        }

        if critical {
            confidence = 0.0
        }

        // Clamp confidence.
        if confidence < 0 {
            confidence = 0
        } else if confidence > 1 {
            confidence = 1
        }

        return RSDegeneracyResult(
            shearSlope: input.shearSlope,
            rowSpanPx: input.rowSpanPx,
            blurStreakPx: input.blurStreakPx,
            phaseRatio: input.phaseRatio,
            ballPx: input.ballPx,
            flickerModulation: input.flickerModulation,
            criticalDegeneracy: critical,
            rsConfidence: confidence
        )
    }

    /// Waggle placement helper.
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

    /// Lightweight shear-slope estimator from local LK flow around the ball.
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
}
