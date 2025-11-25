//
//  DebugControlPanel.swift
//  LaunchLab
//

import SwiftUI

struct DebugControlPanel: View {

    @ObservedObject var config: OverlayConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text("Debug Controls")
                .font(.headline)
                .foregroundColor(.white)

            Toggle("Dots", isOn: $config.showDots)
            Toggle("Velocity", isOn: $config.showVelocity)
            Toggle("RS Corrected", isOn: $config.showRS)
            Toggle("Pose Axes", isOn: $config.showPose)
            Toggle("RS Rows", isOn: $config.showRSRows)
            Toggle("Intrinsics Heatmap", isOn: $config.showIntrinsics)
            Toggle("Ball Lock Debug", isOn: $config.showBallLockDebug)
        }
        .padding(10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
        .toggleStyle(SwitchToggleStyle(tint: .orange))
    }
}
