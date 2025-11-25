//  DebugHUDView.swift
//  LaunchLab
//
//  Lightweight debug HUD + BallLock tuning entry point.
//  Uses CameraManager (for latestFrame) + OverlayConfig (for any overlay settings).
//  No changes to VisionTypes.swift.
//

import SwiftUI

struct DebugHUDView: View {

    // Main camera pipeline (provides latestFrame + ballLockConfig)
    @EnvironmentObject var camera: CameraManager

    // Existing overlay config (kept so other parts of the app can still inject it)
    @EnvironmentObject var overlayConfig: OverlayConfig

    // Local UI state for showing the BallLock tuning panel
    @State private var showBallLockPanel: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {

            // ----------------------------------------------------------------
            // Top-left: basic live telemetry
            // ----------------------------------------------------------------
            VStack(alignment: .leading, spacing: 4) {
                if let frame = camera.latestFrame {
                    Text(String(format: "t = %.3f", frame.timestamp))
                        .font(.system(.caption2, design: .monospaced))

                    Text("dots: \(frame.dots.count)")
                        .font(.system(.caption2, design: .monospaced))

                    Text("tracking: \(trackingLabel(for: frame.trackingState))")
                        .font(.system(.caption2, design: .monospaced))
                } else {
                    Text("No frame")
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(6)
            .padding([.top, .leading], 8)

            // ----------------------------------------------------------------
            // Top-right: controls (includes BallLock Tuning button)
            // ----------------------------------------------------------------
            VStack(alignment: .trailing, spacing: 8) {

                Button(action: {
                    showBallLockPanel.toggle()
                }) {
                    Text("BallLock Tuning")
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding([.top, .trailing], 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // ----------------------------------------------------------------
            // Floating BallLock tuning panel (overlay)
            // ----------------------------------------------------------------
            if showBallLockPanel {
                BallLockTuningPanel(isVisible: $showBallLockPanel)
                    // CameraManager is already in the environment from LaunchLabApp,
                    // so we don't need to re-inject it here.
                    .frame(maxWidth: 320)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Let touches pass through except when interacting with controls.
        .allowsHitTesting(true)
    }

    // MARK: - Helpers

    private func trackingLabel(for state: DotTrackingState) -> String {
        switch state {
        case .initial:  return "initial"
        case .tracking: return "tracking"
        case .lost:     return "lost"
        }
    }
}
