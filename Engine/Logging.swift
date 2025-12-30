//
//  Logging.swift
//  LaunchLab
//
//  Centralized, phase-gated logging for the engine.
//  All console output must route through this file.
//  No direct print() calls elsewhere in the codebase.
//

import Foundation

// MARK: - Log Phases

enum LogPhase: String {
    case camera
    case render
    case detection
    case ballLock
    case authority   // ✅ NEW: ShotAuthorityGate logs
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
        .authority,   // ✅ required for this module
        .shot         // keep if you want lifecycle logs visible
        // .detection,
        // .ballLock,
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

    /// Debug-only logging (guarded by DebugProbe + phase).
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
