//
//  CalibrationFlowView.swift
//  LaunchLab
//

import SwiftUI
import Combine

/// Complete SwiftUI flow for Auto-Calibration v1.
/// Runs outside VisionPipeline and is started manually by the user.
/// Captures ~120 frames, runs calibration, displays results, then persists.
public struct CalibrationFlowView: View {

    @EnvironmentObject private var camera: CameraManager

    @State private var phase: Phase = .idle
    @State private var progress: CGFloat = 0
    @State private var collectedFrames: [VisionFrameData] = []
    @State private var calibration: CalibrationResult? = nil

    @State private var timer: Timer?

    public init() {}

    // ============================================================
    // MARK: - Body
    // ============================================================
    public var body: some View {
        VStack(spacing: 24) {

            Text(title(for: phase))
                .font(.largeTitle)
                .bold()
                .padding(.top, 40)

            progressView

            Spacer()

            switch phase {
            case .idle:
                Button(action: startCollection) {
                    Text("Start Calibration")
                        .font(.title3).bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

            case .collecting:
                Text("Move the ball slightly to gather sample data.\nKeep the camera completely still.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

            case .processing:
                Text("Analyzing frames…")
                    .font(.headline)
                    .padding(.horizontal)

            case .complete:
                if let result = calibration {
                    resultSummary(result)
                        .padding(.horizontal)

                    Button(action: finish) {
                        Text("Done")
                            .font(.title3).bold()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 40)
        .onDisappear { timer?.invalidate() }
    }

    // ============================================================
    // MARK: - Progress View
    // ============================================================
    private var progressView: some View {
        VStack {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .cornerRadius(5)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: progress * UIScreen.main.bounds.width * 0.8,
                           height: 10)
                    .cornerRadius(5)
            }
            .padding(.horizontal)

            Text(progressLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var progressLabel: String {
        switch phase {
        case .idle:        return "Ready"
        case .collecting:  return "Collecting Frames"
        case .processing:  return "Calibrating"
        case .complete:    return "Complete"
        }
    }

    // ============================================================
    // MARK: - Summary UI
    // ============================================================
    @ViewBuilder
    private func resultSummary(_ r: CalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            Group {
                Text("📸 Intrinsics")
                Text("  fx = \(format(r.fx))")
                Text("  fy = \(format(r.fy))")
                Text("  cx = \(format(r.cx))")
                Text("  cy = \(format(r.cy))")
                Text("  refined = \(r.intrinsicsRefined ? "YES" : "NO")")
            }

            Group {
                Text("📐 Camera Tilt")
                Text("  pitch = \(degrees(r.pitch))°")
                Text("  roll  = \(degrees(r.roll))°")
            }

            Group {
                Text("📏 Ball Distance")
                Text("  depth = \(format3(r.ballDistance)) m")
            }

            Group {
                Text("💡 Lighting")
                Text("  gain = \(format3(r.lightingGain))")
            }

            Group {
                Text("📦 Camera Offset")
                Text("  translation = \(vec3(r.translationOffset))")
            }

            Group {
                Text("🧪 Stability")
                Text("  RPE rms = \(format3(r.avgRPERMS))")
                Text("  spin drift = \(format3(r.avgSpinDrift))°")
                Text("  stable = \(r.isStable ? "YES" : "NO")")
            }

            Group {
                Text("📚 RS Timing")
                Text("  readout = \(format6(r.rsReadoutTime)) s")
                Text("  linearity = \(format3(r.rsLinearity))")
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func format(_ x: Float) -> String { String(format: "%.2f", x) }
    private func format3(_ x: Float) -> String { String(format: "%.3f", x) }
    private func format6(_ x: Float) -> String { String(format: "%.6f", x) }

    private func degrees(_ r: Float) -> String {
        String(format: "%.2f", r * 180 / .pi)
    }

    private func vec3(_ v: SIMD3<Float>) -> String {
        String(format: "[%.3f %.3f %.3f]", v.x, v.y, v.z)
    }

    // ============================================================
    // MARK: - Phase Control
    // ============================================================
    private func startCollection() {

        phase = .collecting
        progress = 0
        collectedFrames.removeAll()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in

            if let f = camera.latestFrame {
                collectedFrames.append(f)
            }

            // Progress
            progress = min(1.0, CGFloat(collectedFrames.count) / 120.0)

            // Gather 120 frames
            if collectedFrames.count >= 120 {
                timer?.invalidate()
                beginProcessing()
            }
        }
    }

    private func beginProcessing() {
        phase = .processing
        progress = 0.5

        AutoCalibration.shared.runCalibration(frames: collectedFrames) { result in
            DispatchQueue.main.async {
                self.calibration = result
                self.phase = .complete
                self.progress = 1.0
            }
        }
    }

    private func finish() {
        phase = .idle
        progress = 0
        collectedFrames.removeAll()
        calibration = nil
    }

    // ============================================================
    // MARK: - Phase Enum
    // ============================================================
    private enum Phase {
        case idle
        case collecting
        case processing
        case complete
    }

    // ============================================================
    // MARK: - Title Helpers
    // ============================================================
    private func title(for p: Phase) -> String {
        switch p {
        case .idle:        return "Calibration"
        case .collecting:  return "Collecting Data"
        case .processing:  return "Processing"
        case .complete:    return "Complete"
        }
    }
}