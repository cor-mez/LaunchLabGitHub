//
//  DisappearanceObservabilityLogger.swift
//  LaunchLab
//
//  Logs disappearance context without granting authority.
//

import Foundation

final class DisappearanceObservabilityLogger {

    private var framesObserved: Int = 0
    private var sawBall: Bool = false

    func reset() {
        framesObserved = 0
        sawBall = false
    }

    func observe(ballPresent: Bool) {
        framesObserved += 1
        if ballPresent { sawBall = true }
    }

    func emitSummary() {
        Log.info(
            .shot,
            "[DISAPPEAR_OBS] frames=\(framesObserved) saw_ball=\(sawBall)"
        )
    }
}
