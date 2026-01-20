//
//  Logging.swift
//  LaunchLab
//

import Foundation

enum LogPhase: String {
    case shot
    case detection
    case authority
    case camera
}

enum Log {

    // -------------------------------------------------------------
    // MARK: - Enabled Phases
    // -------------------------------------------------------------

    /// Offline + diagnostics mode
    /// Truth-first, no suppression
    static var enabled: Set<LogPhase> = [
        .shot,
        .detection,
        .authority
    ]

    // -------------------------------------------------------------
    // MARK: - Logging
    // -------------------------------------------------------------

    @inline(__always)
    static func info(
        _ phase: LogPhase,
        _ message: @autoclosure () -> String
    ) {
        guard enabled.contains(phase) else { return }
        Swift.print("[\(phase.rawValue.uppercased())] \(message())")
        fflush(stdout)
    }
}
