//
//  OverlayConfig.swift
//  LaunchLab
//

import Foundation
import Combine

/// Shared configuration for overlay visibility in the app.
final class OverlayConfig: ObservableObject {

    /// Show raw detected dots.
    @Published var showDots: Bool = true

    /// Show LK/velocity vectors.
    @Published var showVelocity: Bool = true

    /// Show RS-corrected points.
    @Published var showRS: Bool = true

    /// Show pose (camera) axes overlay.
    @Published var showPose: Bool = true

    /// Show RS row visualization.
    @Published var showRSRows: Bool = false

    /// Show intrinsics / principal point.
    @Published var showIntrinsics: Bool = false

    /// Show BallLock debug overlay (ROI, state, quality).
    @Published var showBallLockDebug: Bool = true
}
