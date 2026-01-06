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

    static var enabled: Set<LogPhase> = [
        .detection
    ]

    @inline(__always)
    static func info(
        _ phase: LogPhase,
        _ message: @autoclosure () -> String
    ) {
        guard enabled.contains(phase) else { return }
        Swift.print("[\(phase.rawValue.uppercased())] \(message())")
    }
}
