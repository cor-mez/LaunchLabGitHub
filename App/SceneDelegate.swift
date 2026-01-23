//
//  SceneDelegate.swift
//  LaunchLab
//
//  App Boot Entry — PHASE 2 (Headless RS Observability)
//
//  ROLE (STRICT):
//  - Boot Phase-2 capture + FAST9 + RS observability ONLY
//  - No UI
//  - No preview
//  - No Metal presentation
//  - No lifecycle
//  - No authority
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // ---------------------------------------------------------------------
    // MARK: - Phase Probes (mutually exclusive)
    // ---------------------------------------------------------------------

    private var phase1Probe: Phase1CaptureProbe?
    private var phase2Probe: Phase2CaptureRSProbe?

    // ---------------------------------------------------------------------
    // MARK: - Scene Entry
    // ---------------------------------------------------------------------

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {

#if targetEnvironment(macCatalyst)
        // 🚫 macOS Catalyst: no capture, no probes
        return
#else
        guard scene is UIWindowScene else { return }

        // =========================================================
        // 🔀 PHASE SELECTOR
        // =========================================================
        //
        // Exactly ONE probe may be active.
        // Phase-2 is default once wiring is verified.
        //
        // =========================================================

        let runPhase2 = true   // ⬅️ toggle if needed

        if runPhase2 {

            // -----------------------------------------------------
            // PHASE 2 — FAST9 → RS OBSERVABILITY (HEADLESS)
            // -----------------------------------------------------

            let probe = Phase2CaptureRSProbe()
            self.phase2Probe = probe

            // ✅ Correct API: requestedFPS
            probe.start(requestedFPS: 120)

            print("🧪 Phase 2 RS Observability Probe running — headless, no UI")

        } else {

            // -----------------------------------------------------
            // PHASE 1 — CAPTURE CADENCE ONLY (HEADLESS)
            // -----------------------------------------------------

            let probe = Phase1CaptureProbe()
            self.phase1Probe = probe

            probe.start(targetFPS: 120)

            print("🧪 Phase 1 Capture Probe running — headless, no UI")
        }
#endif
    }
}
