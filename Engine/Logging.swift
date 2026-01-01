//
//  Logging.swift
//  LaunchLab
//
//  Centralized, phase-gated logging for the engine.
//  All console output must route through this file.
//  No direct print() calls elsewhere.
//

import Foundation

// MARK: - Log Phases

enum LogPhase: String {
    case camera
    case render
    case detection
    case ballLock
    case shot
    case pose
    case rswindow
    case authority
    case debug
}

// MARK: - Logger

enum Log {

    /// Enabled phases. Adjust to control verbosity.
    static var enabled: Set<LogPhase> = [
        .shot,
        .authority
        // .detection,
        // .ballLock,
        // .debug,
        // .camera,
        // .render,
        // .pose,
        // .rswindow,
    ]

    @inline(__always)
    static func info(
        _ phase: LogPhase,
        _ message: @autoclosure () -> String
    ) {
        guard enabled.contains(phase) else { return }
        Swift.print("[\(phase.rawValue.uppercased())] \(message())")
    }

    @inline(__always)
    static func debug(
        _ phase: LogPhase,
        _ message: @autoclosure () -> String
    ) {
        guard DebugProbe.isEnabled(.capture) else { return }
        guard enabled.contains(phase) else { return }
        Swift.print("[\(phase.rawValue.uppercased())][DEBUG] \(message())")
    }
}
