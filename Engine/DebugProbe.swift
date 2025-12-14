// DebugProbe.swift
import Foundation
import CoreVideo
import Metal

enum DebugPhase: String {
    case capture
    case preview
    case detector
    case tracking
    case pose
    case physics
}

struct DebugProbe {

    static var enabledPhases: Set<DebugPhase> = []

    @inline(__always)
    static func isEnabled(_ phase: DebugPhase) -> Bool {
        enabledPhases.contains(phase)
    }

    @inline(__always)
    static func log(
        _ phase: DebugPhase,
        _ message: @autoclosure () -> String
    ) {
        guard isEnabled(phase) else { return }
    }
}
