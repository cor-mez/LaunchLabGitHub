//
//  ShotPhaseTracker.swift
//  LaunchLab
//
//  Enforces ordered physical phases of a golf strike.
//

import Foundation

final class ShotPhaseTracker {

    enum Phase {
        case idle
        case impulseOnset(time: Double, impactX: CGFloat)
        case awaitingBallEmergence
        case confirmed
        case rejected(reason: String)
    }

    private(set) var phase: Phase = .idle

    func reset() {
        phase = .idle
    }

    func registerImpulse(
        timestamp: Double,
        impactX: CGFloat
    ) {
        guard case .idle = phase else { return }
        phase = .impulseOnset(time: timestamp, impactX: impactX)
    }

    func advanceToAwaitingBall() {
        if case .impulseOnset = phase {
            phase = .awaitingBallEmergence
        }
    }

    func confirm() {
        phase = .confirmed
    }

    func reject(reason: String) {
        phase = .rejected(reason: reason)
    }
}
