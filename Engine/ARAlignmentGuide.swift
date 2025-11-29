// File: Overlays/ARAlignmentGuide.swift
//
//  ARAlignmentGuide.swift
//  LaunchLab
//

import SwiftUI
import simd

struct ARAlignmentGuide: View {

    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var imuService: IMUService

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
                    let (status, tiltHint, distanceHint) = evaluateStatus(frame: frame, imu: imu)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: status))
                                .frame(width: 16, height: 16)

                            Text(label(for: status))
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                        }

                        if let tiltHint = tiltHint {
                            Text(tiltHint)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        if let distanceHint = distanceHint {
                            Text(distanceHint)
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

    private func evaluateStatus(
        frame: VisionFrameData,
        imu: IMUState
    ) -> (AlignmentStatus, String?, String?) {

        let unsafeLighting = camera.unsafeLighting
        let unsafeFrameRate = camera.unsafeFrameRate
        let unsafeThermal = camera.unsafeThermal

        let ballRadius = frame.ballRadiusPx.map { Double($0) } ?? 0.0

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

        // Gravity / tilt
        let g = imu.gravity
        let gNorm = simd_length(g) > 0 ? simd_normalize(g) : SIMD3<Float>(0, -1, 0)
        let targetUp = SIMD3<Float>(0, -1, 0)
        let cosTilt = simd_dot(gNorm, targetUp)

        // Clamp cosTilt to [-1, 1] in Double space and compute degrees.
        let cosTiltClamped = max(-1.0, min(1.0, Double(cosTilt)))
        let tiltRad = acos(cosTiltClamped)
        let tiltDeg = tiltRad * 180.0 / .pi

        let desiredTiltMin: Double = 5.0
        let desiredTiltMax: Double = 25.0

        var tiltHint: String? = nil
        if tiltDeg < desiredTiltMin {
            tiltHint = "Tilt camera more (add roll)"
        } else if tiltDeg > desiredTiltMax {
            tiltHint = "Reduce tilt slightly"
        }

        // Ball radius / distance guidance
        let idealBallMin: Double = 20.0
        let idealBallMax: Double = 40.0
        var distanceHint: String? = nil
        if ballRadius > 0 {
            if ballRadius < idealBallMin {
                distanceHint = "Move phone closer"
            } else if ballRadius > idealBallMax {
                distanceHint = "Move phone farther"
            }
        }

        var redReasons: Int = 0
        var yellowReasons: Int = 0

        // Global safety
        if unsafeLighting || unsafeFrameRate || unsafeThermal {
            redReasons += 1
        }

        // RS geometry
        if rowSpan < 18.0 || shear < 0.10 || rsConf < 0.40 {
            redReasons += 1
        }

        // Flicker
        if flickerMod > 0.20 {
            redReasons += 1
        } else if flickerMod > 0.12 {
            yellowReasons += 1
        }

        // Distance / ball size
        if ballRadius > 0 {
            if ballRadius < 14.0 || ballRadius > 60.0 {
                redReasons += 1
            } else if ballRadius < idealBallMin || ballRadius > idealBallMax {
                yellowReasons += 1
            }
        }

        // Tilt
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

        return (status, tiltHint, distanceHint)
    }
}
