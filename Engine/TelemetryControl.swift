//
//  TelemetryControl.swift
//  LaunchLab
//
//  Global telemetry control flags.
//  NOT part of capture, RS, or authority.
//

import Foundation

enum TelemetryControl {
    /// When true, telemetry writes are ignored.
    /// Capture + RS continue unaffected.
    static var isPaused: Bool = false
}
