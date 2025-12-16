<<<<<<< HEAD
//RSPnPEnvelopeMapping.swift//

import Foundation

public struct RSPnPEnvelopeConfig: Equatable {
    public var enabled: Bool
    public var confidenceThreshold: Float
    public var logTransitionsOnly: Bool

    public init(enabled: Bool = true,
                confidenceThreshold: Float = 12.0,
                logTransitionsOnly: Bool = true) {
        self.enabled = enabled
        self.confidenceThreshold = confidenceThreshold
        self.logTransitionsOnly = logTransitionsOnly
    }
}

/// Minimal “window telemetry” contract so RSIntegration can remain the truth gate.
/// You do NOT change RS‑Window validity logic; you only expose it.
public protocol RSPnPWindowTelemetryProviding {
    var rspnp_isValid: Bool { get }
    var rspnp_invalidReason: String? { get }   // Optional but strongly preferred.

    var rspnp_frameCount: Int { get }
    var rspnp_spanSec: Double { get }
    func rspnp_stalenessSec(nowSec: Double) -> Double

    var rspnp_confidenceMin: Float { get }
    var rspnp_confidenceAvg: Float { get }

    /// Optional “observable motion magnitude” metric. If available, log it.
    var rspnp_motionPx: Double? { get }
}

/// One-call gate + attempt wrapper.
/// - No retries
/// - No smoothing
/// - No pose emission (caller must keep pose dark)
public final class RSPnPEnvelopeMapper {
    public var config: RSPnPEnvelopeConfig
    public let logger: RSPnPEnvelopeLogger

    public init(config: RSPnPEnvelopeConfig,
                logger: RSPnPEnvelopeLogger? = nil) {
        self.config = config
        if let logger {
            self.logger = logger
            self.logger.logTransitionsOnly = config.logTransitionsOnly
        } else {
            self.logger = RSPnPEnvelopeLogger(logTransitionsOnly: config.logTransitionsOnly)
        }
    }

    public func evaluateAndMaybeSolve(
        nowSec: Double,
        smoothedBallLockCount: Float,
        window: RSPnPWindowTelemetryProviding,
        solve: () throws -> (residual: Double, cond: Double)
    ) {
        let telemetry = RSPnPTelemetry(
            timestampSec: nowSec,
            confidenceThreshold: config.confidenceThreshold,
            smoothedBallLockCount: smoothedBallLockCount,
            confidenceMin: window.rspnp_confidenceMin,
            confidenceAvg: window.rspnp_confidenceAvg,
            frameCount: window.rspnp_frameCount,
            spanSec: window.rspnp_spanSec,
            stalenessSec: window.rspnp_stalenessSec(nowSec: nowSec),
            motionPx: window.rspnp_motionPx
        )

        guard config.enabled else {
            logger.skipped(reason: "disabled", telemetry: telemetry)
            return
        }

        guard smoothedBallLockCount >= config.confidenceThreshold else {
            logger.skipped(reason: "conf<threshold", telemetry: telemetry)
            return
        }

        guard window.rspnp_isValid else {
            logger.skipped(reason: window.rspnp_invalidReason ?? "window_invalid", telemetry: telemetry)
            return
        }

        let id = logger.attemptStarted(telemetry: telemetry)

        do {
            let out = try solve()
            // IMPORTANT: do not gate success here; we map, we do not optimize.
            logger.attemptSucceeded(id: id, residual: out.residual, cond: out.cond, telemetry: telemetry)
        } catch {
            logger.attemptFailed(id: id, reason: "\(error)", telemetry: telemetry)
        }
    }
}
=======
//
//  RSPnpEnvelopeMapping.swift
//  LaunchLabGitHub
//
//  Created by Cory Meza on 12/15/25.
//

import Foundation
>>>>>>> 2c38488853e3a13fad4b6fe43eee4a25690abc36
