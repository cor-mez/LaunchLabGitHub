// File: Overlays/OverlayView.swift
//
//  OverlayView.swift
//  LaunchLab
//

import SwiftUI

/// Simple wrapper for future overlay-related developer tools.
/// Currently unused in the main flow but available for expansion.
struct OverlayView: View {

    var body: some View {
        VStack {
            Text("Overlay Debug")
                .font(.headline)
            Text("Use DebugHUD → Developer Tools → Dot Test Mode for dot inspection.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding()
    }
}
