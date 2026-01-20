//
//  SceneDelegate.swift
//  LaunchLab
//
//  App Boot Entry (V1)
//
//  ROLE (STRICT):
//  - Define the single UI boot path
//  - NEVER create, bypass, or imply shot authority
//  - All measurement authority lives in Engine
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {

        // ---------------------------------------------------------
        // macOS (Catalyst) — OFFLINE / NON-INTERACTIVE MODE
        // ---------------------------------------------------------
#if targetEnvironment(macCatalyst)
        // 🚫 No UI, no capture, no authority
        // Offline execution is handled by AppDelegate / Engine bootstrap
        return

        // ---------------------------------------------------------
        // iOS — LIVE CAPTURE MODE
        // ---------------------------------------------------------
#else
        guard let windowScene = scene as? UIWindowScene else { return }

        // Single, orientation-locked window
        let window = OrientationLockedWindow(windowScene: windowScene)

        // Single root view controller.
        // NOTE:
        // - DotTestViewController performs OBSERVATION ONLY.
        // - It does NOT own detection or authority.
        // - All decisions flow through ShotLifecycleController in Engine.
        let rootVC = DotTestViewController()

        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        self.window = window
#endif
    }
}
