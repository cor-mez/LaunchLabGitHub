//
//  IntentState.swift
//  LaunchLab
//
//  Intent is arming-only. Never authorizes shots.
//

enum IntentState {
    case idle
    case candidate(startTime: Double)
    case active(startTime: Double)
    case decay(startTime: Double)
}

extension IntentState {

    /// Armed means RS impulses are allowed to be considered.
    var isArmed: Bool {
        switch self {
        case .active, .decay:
            return true
        default:
            return false
        }
    }
}
