//
//  SceneDelegate.swift
//  LaunchLab
//
//  App Boot Entry — PHASE 1
//
//  ROLE (STRICT):
//  - Boot Phase 1 capture cadence probe ONLY
//  - No UI
//  - No preview
//  - No Metal
//  - No RS
//  - No lifecycle
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var phase1Probe: Phase1CaptureProbe?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {

        // ---------------------------------------------------------
        // macOS (Catalyst) — OFFLINE / NON-INTERACTIVE MODE
        // ---------------------------------------------------------
#if targetEnvironment(macCatalyst)
        // 🚫 No UI, no capture
        return

        // ---------------------------------------------------------
        // iOS — PHASE 1 CAPTURE PROBE
        // ---------------------------------------------------------
#else
        guard scene is UIWindowScene else { return }

        // ❌ Do NOT create a window or view controller
        // ❌ Do NOT attach preview layers
        // ❌ Do NOT touch Metal or RS

        let probe = Phase1CaptureProbe()
        self.phase1Probe = probe

        // 🔬 Start clean-room capture cadence test
        probe.start(targetFPS: 120)

        print("🧪 Phase 1 Capture Probe running — no UI attached")
#endif
    }
}
