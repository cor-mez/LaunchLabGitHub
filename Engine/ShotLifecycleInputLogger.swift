//
//  ShotLifecycleInputLogger.swift
//  LaunchLab
//
//  Observability-only logger for lifecycle inputs.
//  NO authority, NO decisions, NO mutation.
//

import Foundation

enum ShotLifecycleInputLogger {

    static func log(
        timestamp: Double,
        state: ShotLifecycleState,
        motionPhase: MotionDensityPhase,
        ballSpeedPxPerSec: Double?,
        ballLockConfidence: Float
    ) {

        let speedStr = ballSpeedPxPerSec
            .map { String(format: "%.1f", $0) } ?? "nil"

        Log.info(
            .shot,
            "lifecycle_input " +
            "t=\(fmt(timestamp)) " +
            "state=\(state.rawValue) " +
            "phase=\(motionPhase.rawValue) " +
            "v_px_s=\(speedStr) " +
            "conf=\(fmt(ballLockConfidence))"
        )
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.4f", v)
    }

    private static func fmt(_ v: Float) -> String {
        String(format: "%.2f", v)
    }
}
