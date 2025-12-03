// File: App/DebugHUDView.swift
//
//  DebugHUDView.swift
//  LaunchLab
//

import SwiftUI

struct DebugHUDView: View {

    @EnvironmentObject private var camera: CameraManager

    @State private var showBallLockTuning: Bool = false
    @State private var showDotTestMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let frame = camera.latestFrame {
                Text(String(format: "t = %.3f", frame.timestamp))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                Text("dots: \(frame.dots.count)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
            } else {
                Text("t = —")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                Text("dots: 0")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
            }

            Text("tracking:")
                .font(.system(size: 12, weight: .regular, design: .monospaced))

            Spacer().frame(height: 8)

            HStack(spacing: 8) {
                Button("BallLock Tuning") {
                    showBallLockTuning = true
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)

                Menu("Developer Tools") {
                    Button("Dot Test Mode") {
                        showDotTestMode = true
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.5))
        )
        .sheet(isPresented: $showBallLockTuning) {
            BallLockTuningPanel()
                .environmentObject(camera)
        }
        .sheet(isPresented: $showDotTestMode) {
            NavigationStack {
                DotTestView()
                    .environmentObject(camera)
            }
        }
    }
}
