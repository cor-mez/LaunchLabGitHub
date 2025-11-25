// File: App/BallLockTuningPanel.swift
// BallLockTuningPanel — live BallLock tuning HUD (sliders + live telemetry).
// Uses BallLockConfig (local) and VisionFrameData residuals (100/101/102).

import SwiftUI

struct BallLockTuningPanel: View {

    @EnvironmentObject var cameraManager: CameraManager

    // Optional visibility binding; call sites can ignore and use default.
    @Binding var isVisible: Bool

    init(isVisible: Binding<Bool> = .constant(true)) {
        self._isVisible = isVisible
    }

    // Convenience access
    private var config: BallLockConfig { cameraManager.ballLockConfig }

    // MARK: - Telemetry model

    private struct Telemetry {
        var hasData: Bool = false
        var stateCode: Int = 0
        var stateLabel: String {
            switch stateCode {
            case 0: return "SEARCH"
            case 1: return "CAND"
            case 2: return "LOCKED"
            case 3: return "COOLDN"
            default: return "UNK"
            }
        }
        var quality: Double = 0
        var symmetry: Double = 0
        var count: Int = 0
        var radius: Double = 0
    }

    private var telemetry: Telemetry {
        guard let frame = cameraManager.latestFrame,
              let residuals = frame.residuals else {
            return Telemetry()
        }

        var t = Telemetry()

        for r in residuals {
            switch r.id {
            case 101:
                // error.x = quality, error.y = stateCode
                t.quality = Double(r.error.x)
                t.stateCode = Int(r.error.y)

            case 102:
                // error.x = symmetryScore, error.y = radiusPx, weight = count
                t.symmetry = Double(r.error.x)
                t.radius = Double(r.error.y)
                t.count = Int(r.weight)

            default:
                continue
            }
        }

        t.hasData = true
        return t
    }

    // MARK: - Body

    var body: some View {
        let t = telemetry

        return VStack(alignment: .leading, spacing: 12) {

            // Header + state
            HStack {
                Text("BallLock Tuning")
                    .font(.headline)
                Spacer()
                Text(t.stateLabel)
                    .font(.system(.caption, design: .monospaced))
                    .padding(4)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(4)
            }

            if t.hasData {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "Q:  %.2f", t.quality))
                        .font(.system(.caption, design: .monospaced))
                    Text(String(format: "SYM: %.2f   CNT: %d   RAD: %.1fpx",
                                t.symmetry, t.count, t.radius))
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
            }

            Divider()

            ScrollView {

                // MARK: Cluster
                Group {
                    Text("Cluster")
                        .font(.subheadline).bold()

                    Stepper(
                        value: Binding(
                            get: { config.minCorners },
                            set: { config.minCorners = $0 }
                        ),
                        in: 0...64
                    ) {
                        Text("Min corners: \(config.minCorners)")
                    }

                    Stepper(
                        value: Binding(
                            get: { config.maxCorners },
                            set: { config.maxCorners = $0 }
                        ),
                        in: 0...64
                    ) {
                        Text("Max corners: \(config.maxCorners)")
                    }

                    Slider(
                        value: Binding(
                            get: { config.minRadiusPx },
                            set: { config.minRadiusPx = $0 }
                        ),
                        in: 0...200,
                        step: 1
                    ) {
                        Text("Min radius px")
                    }
                    Text("Min radius: \(Int(config.minRadiusPx)) px")
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.maxRadiusPx },
                            set: { config.maxRadiusPx = $0 }
                        ),
                        in: 0...300,
                        step: 1
                    ) {
                        Text("Max radius px")
                    }
                    Text("Max radius: \(Int(config.maxRadiusPx)) px")
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.minQualityToEnterLock },
                            set: { config.minQualityToEnterLock = $0 }
                        ),
                        in: 0...1,
                        step: 0.01
                    ) {
                        Text("Min quality to consider")
                    }
                    Text(String(format: "Min Q for lock candidate: %.2f", config.minQualityToEnterLock))
                        .font(.caption2)
                }

                Divider().padding(.vertical, 4)

                // MARK: State Machine
                Group {
                    Text("State Machine")
                        .font(.subheadline).bold()

                    Slider(
                        value: Binding(
                            get: { config.qLock },
                            set: { config.qLock = $0 }
                        ),
                        in: 0...1,
                        step: 0.01
                    ) {
                        Text("qLock")
                    }
                    Text(String(format: "qLock: %.2f", config.qLock))
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.qStay },
                            set: { config.qStay = $0 }
                        ),
                        in: 0...1,
                        step: 0.01
                    ) {
                        Text("qStay")
                    }
                    Text(String(format: "qStay: %.2f", config.qStay))
                        .font(.caption2)

                    Stepper(
                        value: Binding(
                            get: { config.lockAfterN },
                            set: { config.lockAfterN = $0 }
                        ),
                        in: 1...20
                    ) {
                        Text("Lock after N: \(config.lockAfterN)")
                    }

                    Stepper(
                        value: Binding(
                            get: { config.unlockAfterM },
                            set: { config.unlockAfterM = $0 }
                        ),
                        in: 1...20
                    ) {
                        Text("Unlock after M: \(config.unlockAfterM)")
                    }
                }

                Divider().padding(.vertical, 4)

                // MARK: Smoothing / ROI
                Group {
                    Text("Smoothing / ROI")
                        .font(.subheadline).bold()

                    Slider(
                        value: Binding(
                            get: { config.alphaCenter },
                            set: { config.alphaCenter = $0 }
                        ),
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Centroid alpha")
                    }
                    Text(String(format: "α center: %.2f", config.alphaCenter))
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.roiRadiusFactor },
                            set: { config.roiRadiusFactor = $0 }
                        ),
                        in: 0.5...4.0,
                        step: 0.1
                    ) {
                        Text("ROI radius factor")
                    }
                    Text(String(format: "ROI factor: %.2f×", config.roiRadiusFactor))
                        .font(.caption2)
                }

                Divider().padding(.vertical, 4)

                // MARK: Weights
                Group {
                    Text("Weights")
                        .font(.subheadline).bold()

                    Slider(
                        value: Binding(
                            get: { config.countWeight },
                            set: { config.countWeight = $0 }
                        ),
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Count weight")
                    }
                    Text(String(format: "Count w: %.2f", config.countWeight))
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.radiusWeight },
                            set: { config.radiusWeight = $0 }
                        ),
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Radius weight")
                    }
                    Text(String(format: "Radius w: %.2f", config.radiusWeight))
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.symmetryWeight },
                            set: { config.symmetryWeight = $0 }
                        ),
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Symmetry weight")
                    }
                    Text(String(format: "Symmetry w: %.2f", config.symmetryWeight))
                        .font(.caption2)
                }

                Divider().padding(.vertical, 4)

                // MARK: Velocity (v1: exposed, default OFF)
                Group {
                    Text("Velocity")
                        .font(.subheadline).bold()

                    Toggle("Enable velocity coherence", isOn: Binding(
                        get: { config.enableVelocityCoherence },
                        set: { config.enableVelocityCoherence = $0 }
                    ))

                    Slider(
                        value: Binding(
                            get: { config.velocityAngleTolerance },
                            set: { config.velocityAngleTolerance = $0 }
                        ),
                        in: 0...60,
                        step: 1
                    ) {
                        Text("Angle tolerance (°)")
                    }
                    Text(String(format: "Angle tol: %.0f°", config.velocityAngleTolerance))
                        .font(.caption2)

                    Slider(
                        value: Binding(
                            get: { config.velocityMagnitudeRatioTolerance },
                            set: { config.velocityMagnitudeRatioTolerance = $0 }
                        ),
                        in: 0...2.0,
                        step: 0.05
                    ) {
                        Text("Magnitude ratio tol")
                    }
                    Text(String(format: "Mag ratio tol: %.2f", config.velocityMagnitudeRatioTolerance))
                        .font(.caption2)
                }

                Divider().padding(.vertical, 4)

                // MARK: Debug toggles
                Group {
                    Text("Debug")
                        .font(.subheadline).bold()

                    Toggle("Show BallLock overlay", isOn: Binding(
                        get: { config.showBallLockDebug },
                        set: { config.showBallLockDebug = $0 }
                    ))

                    Toggle("Breadcrumb", isOn: Binding(
                        get: { config.showBallLockBreadcrumb },
                        set: { config.showBallLockBreadcrumb = $0 }
                    ))

                    Toggle("Text HUD", isOn: Binding(
                        get: { config.showBallLockTextHUD },
                        set: { config.showBallLockTextHUD = $0 }
                    ))

                    Toggle("Cluster dots", isOn: Binding(
                        get: { config.showClusterDots },
                        set: { config.showClusterDots = $0 }
                    ))

                    Toggle("Console logging", isOn: Binding(
                        get: { config.showBallLockLogging },
                        set: { config.showBallLockLogging = $0 }
                    ))

                    Button("Reset BallLock") {
                        config.requestReset()
                    }
                    .font(.system(.footnote, design: .monospaced))
                    .padding(.top, 4)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    isVisible = false
                }
                .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
