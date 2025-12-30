//
//  FounderTelemetryObserver.swift
//  LaunchLab
//
//  Engine → App telemetry boundary
//

import Foundation

protocol FounderTelemetryObserver: AnyObject {

    func didUpdateFounderTelemetry(_ telemetry: FounderFrameTelemetry)

    func didCompleteShot(
        _ summary: EngineShotSummary,
        history: [ShotRecord],
        summaries: [EngineShotSummary]
    )
}

// Default empty implementation so conformers can ignore completion events
extension FounderTelemetryObserver {

    func didCompleteShot(
        _ summary: EngineShotSummary,
        history: [ShotRecord],
        summaries: [EngineShotSummary]
    ) {}
}
