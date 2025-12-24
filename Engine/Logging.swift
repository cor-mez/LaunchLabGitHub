//
//  Logging.swift
//  LaunchLab
//
//  Centralized, phase-gated logging for the engine.
//  All console output should route through this file.
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
    case debug
}

// MARK: - Logger

enum Log {

    /// Enabled log phases.
    /// Modify this set to control console verbosity globally.
    static var enabled: Set<LogPhase> = [
        .detection,
        .ballLock,
        .shot
        // .camera,
        // .render,
        // .pose,
        // .rswindow,
        // .debug
    ]

    /// Primary logging entry point.
    /// Uses autoclosure to avoid string construction cost when disabled.
    @inline(__always)
    static func info(
        _ phase: LogPhase,
        _ message: @autoclosure () -> String
    ) {
        guard enabled.contains(phase) else { return }
        Swift.print("[\(phase.rawValue.uppercased())] \(message())")
    }

    /// Explicit debug-only logging.
    /// Intended for temporary instrumentation.
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
