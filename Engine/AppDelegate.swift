//
//  AppDelegate.swift
//  LaunchLab
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // -----------------------------------------------------
        // Telemetry command observers (SAFE, NON-HOT PATH)
        // -----------------------------------------------------

        NotificationCenter.default.addObserver(
            forName: .telemetryPause,
            object: nil,
            queue: nil
        ) { _ in
            TelemetryControl.isPaused = true
            print("⏸ Telemetry paused")
        }

        NotificationCenter.default.addObserver(
            forName: .telemetryDump,
            object: nil,
            queue: nil
        ) { _ in
            TelemetryDump.dumpCSV()
        }

        return true
    }
}
