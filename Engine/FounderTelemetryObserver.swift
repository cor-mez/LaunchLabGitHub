//
//  FounderTelemetryObserver.swift
//

import Foundation

protocol FounderTelemetryObserver: AnyObject {
    func didUpdateFounderTelemetry(_ telemetry: FounderFrameTelemetry)
    func didCompleteShot(
        _ summary: ShotSummary,
        history: [ShotRecord],
        summaries: [ShotSummary]
    )
}

// Default empty implementation so conformers can ignore it
extension FounderTelemetryObserver {
    func didCompleteShot(
        _ summary: ShotSummary,
        history: [ShotRecord],
        summaries: [ShotSummary]
    ) {}
}
