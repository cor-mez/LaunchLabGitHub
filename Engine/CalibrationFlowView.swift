//
//  CalibrationFlowView.swift
//  LaunchLab
//

import SwiftUI

public struct CalibrationFlowView: View {

    @EnvironmentObject private var camera: CameraManager

    @State private var phase: Phase = .idle
    @State private var progress: CGFloat = 0
    @State private var frames: [VisionFrameData] = []
    @State private var result: CalibrationResult? = nil

    @State private var timer: Timer?

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Body
    // ------------------------------------------------------------
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
                Button("Start Calibration", action: start)
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

            case .collecting:
                Text("Move the ball slightly.\nKeep the camera still.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

            case .processing:
                Text("Analyzing…")
                    .font(.headline)

            case .complete:
                if let r = result {
                    resultSummary(r)
                        .padding(.horizontal)

                    Button("Done", action: finish)
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 40)
        .onDisappear { timer?.invalidate() }
    }

    // ------------------------------------------------------------
    // MARK: - Progress UI
    // ------------------------------------------------------------
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
        case .idle:        "Ready"
        case .collecting:  "Collecting Frames"
        case .processing:  "Calibrating"
        case .complete:    "Complete"
        }
    }

    // ------------------------------------------------------------
    // MARK: - Summary UI (Canonical CalibrationResult Only)
    // ------------------------------------------------------------
    private func resultSummary(_ r: CalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            Group {
                Text("📐 Camera Tilt")
                Text("  roll  = \(deg(r.roll))°")
                Text("  pitch = \(deg(r.pitch))°")
                Text("  yaw   = \(deg(r.yawOffset))°")
            }

            Group {
                Text("📏 Camera → Tee")
                Text("  distance = \(fmt(r.cameraToTeeDistance)) m")
            }

            Group {
                Text("📍 Launch Origin (camera frame)")
                Text("  [\(fmt(r.launchOrigin.x)), \(fmt(r.launchOrigin.y)), \(fmt(r.launchOrigin.z))]")
            }

            Group {
                Text("🌎 World Alignment Matrix")
                ForEach(0..<3, id: \.self) { row in
                    Text("  [\(fmt(r.worldAlignmentR[row,0])), \(fmt(r.worldAlignmentR[row,1])), \(fmt(r.worldAlignmentR[row,2]))]")
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    private func fmt(_ x: Float) -> String { String(format: "%.3f", x) }
    private func deg(_ r: Float) -> String { String(format: "%.2f", r * 180 / .pi) }

    // ------------------------------------------------------------
    // MARK: - Flow Control
    // ------------------------------------------------------------
    private func start() {
        phase = .collecting
        progress = 0
        frames.removeAll()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            if let f = camera.latestFrame {
                frames.append(f)
            }

            progress = min(1.0, CGFloat(frames.count) / 120.0)

            if frames.count >= 120 {
                timer?.invalidate()
                process()
            }
        }
    }

    private func process() {
        phase = .processing
        progress = 0.5

        AutoCalibration.shared.runCalibration(frames: frames) { r in
            DispatchQueue.main.async {
                self.result = r
                self.phase = .complete
                self.progress = 1.0
            }
        }
    }

    private func finish() {
        phase = .idle
        progress = 0
        frames.removeAll()
        result = nil
    }

    // ------------------------------------------------------------
    // MARK: - Enum
    // ------------------------------------------------------------
    private enum Phase {
        case idle, collecting, processing, complete
    }

    private func title(for p: Phase) -> String {
        switch p {
        case .idle:        "Calibration"
        case .collecting:  "Collecting Data"
        case .processing:  "Processing"
        case .complete:    "Complete"
        }
    }
}
