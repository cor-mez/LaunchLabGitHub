//
//  IntentState.swift
//  LaunchLab
//
//  Explicit intent authority with timestamped transitions
//

enum IntentState {
    case idle
    case candidate(startTime: Double)
    case active(startTime: Double)
    case decay(startTime: Double)
}
