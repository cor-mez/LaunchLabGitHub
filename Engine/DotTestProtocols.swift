//
//  DotTestProtocols.swift
//

import Foundation

protocol DotTestFounderTelemetryObserver: AnyObject {
    func didUpdateFounderTelemetry(_ telemetry: FounderFrameTelemetry)
    func didCompleteShot(
        _ summary: ShotSummary,
        history: [ShotRecord],
        summaries: [ShotSummary]
    )
}

extension DotTestFounderTelemetryObserver {
    func didCompleteShot(
        _ summary: ShotSummary,
        history: [ShotRecord],
        summaries: [ShotSummary]
    ) {}
}
