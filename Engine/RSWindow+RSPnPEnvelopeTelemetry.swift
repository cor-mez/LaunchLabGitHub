//
//  RSWindow+RSPnPEnvelopeTelemetry.swift
//  Engine
//
//  Telemetry exposure only — DO NOT change validity logic.
//

import Foundation
import CoreGraphics

extension RSWindowSnapshot: RSPnPWindowTelemetryProviding {

    var rspnp_isValid: Bool { self.isValid }

    var rspnp_invalidReason: String? { nil } // Optional; keep nil unless you already track explicit reasons.

    var rspnp_frameCount: Int { self.frameCount }

    var rspnp_spanSec: Double { self.spanSec }

    func rspnp_stalenessSec(nowSec: Double) -> Double {
        guard let last = frames.last else { return .infinity }
        return max(0, nowSec - last.timestampSec)
    }

    var rspnp_confidenceMin: Float {
        frames.map { $0.confidence }.min() ?? 0
    }

    var rspnp_confidenceAvg: Float {
        guard !frames.isEmpty else { return 0 }
        let sum = frames.reduce(Float(0)) { $0 + $1.confidence }
        return sum / Float(frames.count)
    }

    /// Observable motion magnitude (pixel displacement across the window).
    var rspnp_motionPx: Double? {
        guard let first = frames.first, let last = frames.last else { return nil }
        let dx = Double(last.ballCenter2D.x - first.ballCenter2D.x)
        let dy = Double(last.ballCenter2D.y - first.ballCenter2D.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
