//
//  AppDelegate.swift
//  LaunchLab
//
//  iOS + Mac Catalyst compatible
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

#if targetEnvironment(macCatalyst)
        // 🚫 Do NOT launch UI
        // ✅ Run offline analysis immediately
        DispatchQueue.main.async {
            MacOfflineBootstrap.run()
            exit(0)
        }
        return true
#else
        // iOS normal launch
        return true
#endif
    }
}
