//
//  OverlayCoordinator.swift
//  LaunchLab
//

import Foundation

enum OverlayCoordinator {

    /// Build the ordered list of overlay layers based on the current config.
    /// Layers are ordered from bottom (first) to top (last).
    static func makeOverlays(config: OverlayConfig) -> [BaseOverlayLayer] {

        var layers: [BaseOverlayLayer] = []

        // Base analysis overlays (bottom-most)
        if config.showDots {
            layers.append(DotOverlayLayer())
        }

        if config.showVelocity {
            layers.append(VelocityOverlayLayer())
        }

        if config.showRS {
            layers.append(RSCorrectedOverlayLayer())
        }

        if config.showPose {
            layers.append(PoseAxesOverlayLayer())
        }

        if config.showRSRows {
            layers.append(RSRowOverlayLayer())
        }

        if config.showIntrinsics {
            layers.append(IntrinsicsHeatmapLayer())
        }

        // BallLock debug overlay (top-most when enabled)
        if config.showBallLockDebug {
            layers.append(BallLockOverlayLayer())
        }

        return layers
    }
}
