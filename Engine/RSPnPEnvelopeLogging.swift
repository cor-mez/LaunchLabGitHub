import Foundation

public protocol RSPnPLogSink {
    func emit(_ line: String)
}

public struct PrintRSPnPLogSink: RSPnPLogSink {
    public init() {}
    public func emit(_ line: String) {
        Swift.print(line)
    }
}

/// Telemetry snapshot captured at the moment we decide to skip/attempt/fail/succeed.
public struct RSPnPTelemetry: Equatable {
    public var timestampSec: Double

    // Gate inputs
    public var confidenceThreshold: Float
    public var smoothedBallLockCount: Float

    // Window / confidence stats
    public var confidenceMin: Float
    public var confidenceAvg: Float
    public var frameCount: Int
    public var spanSec: Double
    public var stalenessSec: Double

    // Optional but strongly recommended for residual correlation vs motion magnitude.
    public var motionPx: Double?

    public init(
        timestampSec: Double,
        confidenceThreshold: Float,
        smoothedBallLockCount: Float,
        confidenceMin: Float,
        confidenceAvg: Float,
        frameCount: Int,
        spanSec: Double,
        stalenessSec: Double,
        motionPx: Double? = nil
    ) {
        self.timestampSec = timestampSec
        self.confidenceThreshold = confidenceThreshold
        self.smoothedBallLockCount = smoothedBallLockCount
        self.confidenceMin = confidenceMin
        self.confidenceAvg = confidenceAvg
        self.frameCount = frameCount
        self.spanSec = spanSec
        self.stalenessSec = stalenessSec
        self.motionPx = motionPx
    }
}

/// Strict logging for RS‑PnP envelope mapping.
/// Emits only these transitions:
///   [RSPNP] skipped — reason=<reason>
///   [RSPNP] attempted
///   [RSPNP] failed — reason=<reason>
///   [RSPNP] succeeded — residual=<v> cond=<v>
public final class RSPnPEnvelopeLogger {

    public var logTransitionsOnly: Bool

    private let sink: RSPnPLogSink
    private var lastSuppressedSignature: String?
    private var attemptID: UInt64 = 0

    public init(logTransitionsOnly: Bool = true, sink: RSPnPLogSink = PrintRSPnPLogSink()) {
        self.logTransitionsOnly = logTransitionsOnly
        self.sink = sink
    }

    // MARK: - Required events

    public func skipped(reason: String, telemetry: RSPnPTelemetry) {
        // Transitions-only applies mainly to skip spam.
        let signature = "skipped|\(reason)"
        if logTransitionsOnly && lastSuppressedSignature == signature {
            return
        }
        lastSuppressedSignature = signature

        sink.emit("[RSPNP] skipped — reason=\(reason) \(formatTelemetry(telemetry))")
    }

    @discardableResult
    public func attemptStarted(telemetry: RSPnPTelemetry) -> UInt64 {
        attemptID &+= 1
        let id = attemptID
        lastSuppressedSignature = "attempted"

        sink.emit("[RSPNP] attempted id=\(id) \(formatTelemetry(telemetry))")
        return id
    }

    public func attemptFailed(
        id: UInt64,
        reason: String,
        telemetry: RSPnPTelemetry,
        residual: Double? = nil,
        cond: Double? = nil
    ) {
        lastSuppressedSignature = "failed|\(reason)"

        var extras: [String] = []
        if let residual { extras.append("residual=\(fmt(residual, 4))") }
        if let cond { extras.append("cond=\(fmt(cond, 3))") }
        let extraStr = extras.isEmpty ? "" : " " + extras.joined(separator: " ")

        sink.emit("[RSPNP] failed — reason=\(reason) id=\(id)\(extraStr) \(formatTelemetry(telemetry))")
    }

    public func attemptSucceeded(id: UInt64, residual: Double, cond: Double, telemetry: RSPnPTelemetry) {
        lastSuppressedSignature = "succeeded"

        sink.emit("[RSPNP] succeeded — residual=\(fmt(residual, 4)) cond=\(fmt(cond, 3)) id=\(id) \(formatTelemetry(telemetry))")
    }

    // MARK: - Formatting

    private func formatTelemetry(_ t: RSPnPTelemetry) -> String {
        var parts: [String] = []
        parts.append("t=\(fmt(t.timestampSec, 3))")
        parts.append("confThr=\(fmt(Double(t.confidenceThreshold), 2))")
        parts.append("conf=\(fmt(Double(t.smoothedBallLockCount), 2))")
        parts.append("confMin=\(fmt(Double(t.confidenceMin), 2))")
        parts.append("confAvg=\(fmt(Double(t.confidenceAvg), 2))")
        parts.append("frames=\(t.frameCount)")
        parts.append("spanSec=\(fmt(t.spanSec, 3))")
        parts.append("staleSec=\(fmt(t.stalenessSec, 3))")
        if let motion = t.motionPx {
            parts.append("motionPx=\(fmt(motion, 2))")
        }
        return parts.joined(separator: " ")
    }

    private func fmt(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
