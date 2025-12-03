// File: Overlays/ARAlignmentGuide.swift
//
//  ARAlignmentGuide.swift
//  LaunchLab
//

import SwiftUI
import simd

struct ARAlignmentGuide: View {

    @EnvironmentObject var camera: CameraManager
    @ObservedObject private var imuService = IMUService.shared

    private enum AlignmentStatus {
        case red
        case yellow
        case green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let frame = camera.latestFrame {
                    let imu = imuService.currentState
                    let (status, primaryHint, secondaryHint) = evaluateStatus(frame: frame, imu: imu)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: status))
                                .frame(width: 16, height: 16)

                            Text(label(for: status))
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                        }

                        if let primaryHint = primaryHint {
                            Text(primaryHint)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        if let secondaryHint = secondaryHint {
                            Text(secondaryHint)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.6))
                    )
                    .padding(.top, 12)
                    .padding(.leading, 12)

                    if status == .green {
                        Circle()
                            .strokeBorder(Color.green, lineWidth: 2)
                            .frame(width: 40, height: 40)
                            .position(x: geo.size.width * 0.5,
                                      y: geo.size.height * 0.65)
                            .shadow(color: .green.opacity(0.7), radius: 4)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func color(for status: AlignmentStatus) -> Color {
        switch status {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }

    private func label(for status: AlignmentStatus) -> String {
        switch status {
        case .red: return "ALIGN: BAD"
        case .yellow: return "ALIGN: OK"
        case .green: return "ALIGN: GOOD"
        }
    }

    /// Returns: (status, primaryHint, secondaryHint)
    private func evaluateStatus(
        frame: VisionFrameData,
        imu: IMUState
    ) -> (AlignmentStatus, String?, String?) {

        let unsafeLighting = camera.unsafeLighting
        let unsafeFrameRate = camera.unsafeFrameRate
        let unsafeThermal = camera.unsafeThermal

        // Ball size estimate in pixels (if BallLock / cluster has seen it)
        // V1.5: ballRadiusPx removed — use cluster radius when available
        let ballRadius: Double = {
            if let residuals = frame.residuals,
               let roi = residuals.first(where: { $0.id == 100 }) {
                return Double(roi.weight)   // weight stores ROI radiusPx
            }
            return 0.0
        }()
        // RS / flicker metrics from residuals
        var shear: Double = 0
        var rowSpan: Double = 0
        var rsConf: Double = 0
        var flickerMod: Double = 0

        if let residuals = frame.residuals {
            if let rsR = residuals.first(where: { $0.id == 104 }) {
                shear = Double(rsR.error.x)
                rowSpan = Double(rsR.error.y)
                rsConf = Double(rsR.weight)
            }
            if let flR = residuals.first(where: { $0.id == 105 }) {
                flickerMod = Double(flR.error.y)
            }
        }

        // Gravity / tilt: how far are we from "portrait with a bit of roll"
        let g = imu.gravity
        let gNorm = simd_length(g) > 0 ? simd_normalize(g) : SIMD3<Float>(0, -1, 0)
        let targetUp = SIMD3<Float>(0, -1, 0)
        let cosTilt = simd_dot(gNorm, targetUp)

        let cosTiltClamped = max(-1.0, min(1.0, Double(cosTilt)))
        let tiltRad = acos(cosTiltClamped)
        let tiltDeg = tiltRad * 180.0 / .pi

        let desiredTiltMin: Double = 5.0   // roll-ish tilt
        let desiredTiltMax: Double = 25.0

        // ------------------------------------------------------------------
        // Hints: angle / tilt + distance / placement
        // ------------------------------------------------------------------

        var tiltHintParts: [String] = []
        if tiltDeg < desiredTiltMin {
            tiltHintParts.append("Tilt camera more (add roll)")
        } else if tiltDeg > desiredTiltMax {
            tiltHintParts.append("Reduce tilt slightly")
        }

        // RS geometry → "more behind ball" guidance
        // Very small rowSpan + low shear means too flat / too side-on.
        if rowSpan > 0 {
            if rowSpan < 14.0 || shear < 0.08 {
                tiltHintParts.append("Move phone more behind ball (8–12 ft, 20–35°)")
            }
        } else {
            // No RS yet: give a generic geometry hint once user is staring at the scene.
            tiltHintParts.append("Place phone 8–12 ft behind ball and 2–4 ft to the side")
        }

        let primaryHint: String? = tiltHintParts.isEmpty ? nil
            : tiltHintParts.joined(separator: " · ")

        // Distance / "move closer / farther" guidance from ballRadius if we have it.
        var secondaryHint: String? = nil
        let idealBallMin: Double = 20.0
        let idealBallMax: Double = 40.0

        if ballRadius > 0 {
            if ballRadius < idealBallMin {
                secondaryHint = "Move phone closer (ball should nearly fill the white circle)"
            } else if ballRadius > idealBallMax {
                secondaryHint = "Move phone farther (ball should shrink inside the circle)"
            } else {
                secondaryHint = "Distance OK — keep ball centered in the white circle"
            }
        } else {
            // We don't yet have a reliable radius → give clear placement instructions.
            secondaryHint = "Put the 72‑dot ball fully inside the white circle"
        }

        // ------------------------------------------------------------------
        // Status colour: combine safety + geometry seriousness
        // ------------------------------------------------------------------

        var redReasons: Int = 0
        var yellowReasons: Int = 0

        if unsafeLighting || unsafeFrameRate || unsafeThermal {
            redReasons += 1
        }

        if rowSpan > 0 {
            if rowSpan < 14.0 || shear < 0.05 || rsConf < 0.30 {
                redReasons += 1
            } else if rowSpan < 18.0 || shear < 0.10 || rsConf < 0.50 {
                yellowReasons += 1
            }
        }

        if flickerMod > 0.20 {
            redReasons += 1
        } else if flickerMod > 0.12 {
            yellowReasons += 1
        }

        if ballRadius > 0 {
            if ballRadius < 14.0 || ballRadius > 60.0 {
                redReasons += 1
            } else if ballRadius < idealBallMin || ballRadius > idealBallMax {
                yellowReasons += 1
            }
        }

        if tiltDeg < 2.0 || tiltDeg > 35.0 {
            redReasons += 1
        } else if tiltDeg < desiredTiltMin || tiltDeg > desiredTiltMax {
            yellowReasons += 1
        }

        let status: AlignmentStatus
        if redReasons > 0 {
            status = .red
        } else if yellowReasons > 0 {
            status = .yellow
        } else {
            status = .green
        }

        return (status, primaryHint, secondaryHint)
    }
}
