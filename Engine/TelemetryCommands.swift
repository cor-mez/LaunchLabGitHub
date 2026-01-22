//
//  TelemetryCommands.swift
//  LaunchLab
//
//  Notification-based telemetry control.
//  LLDB-safe. No symbol resolution required.
//

import Foundation

extension Notification.Name {
    static let telemetryPause = Notification.Name("launchlab.telemetry.pause")
    static let telemetryDump  = Notification.Name("launchlab.telemetry.dump")
}
