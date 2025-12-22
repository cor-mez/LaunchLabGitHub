import Foundation
import CoreGraphics

struct FounderFrameTelemetry {
    let roi: CGRect
    let fullSize: CGSize
    let ballLocked: Bool
    let confidence: Float
    let center: CGPoint?
    let mdgDecision: MarkerlessDiscriminationGates.Decision?
    let motionGatePxPerSec: Double
    let timestampSec: Double
}

enum ImpactClassification: String {
    case clean = "Clean"
    case thin = "Thin"
    case toe  = "Toe"
    case heel = "Heel"
    case unknown = "Unknown"
}

struct ShotMeasuredData {
    let ballSpeedPxPerSec: Double?
    let launchAngleDeg: Double?
    let launchDirectionDeg: Double?
    let stabilityIndex: Int
    let impact: ImpactClassification
    let pixelDisplacement: Double?
    let frameIntervalSec: Double?
}

struct ShotEstimatedData {
    let carryDistance: Double?
    let apexHeight: Double?
    let dispersion: Double?
}

enum ShotStatus {
    case measured
    case estimated
    case refused
}

struct ShotRecord {
    let id: Int
    let timestamp: Date
    let measured: ShotMeasuredData?
    let estimated: ShotEstimatedData?
    let status: ShotStatus
    let refusalReasons: [String]
}

enum ShotLifecycleState: Equatable {
    case idle
    case armed(confidence: Float)
    case captured(ShotRecord)
    case summary(ShotRecord)

    static func == (lhs: ShotLifecycleState, rhs: ShotLifecycleState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case let (.armed(a), .armed(b)): return a == b
        case let (.captured(a), .captured(b)): return a.id == b.id
        case let (.summary(a), .summary(b)): return a.id == b.id
        default: return false
        }
    }
}

struct ShotEvent {
    let shot: ShotRecord?
    let lifecycle: ShotLifecycleState
}

enum FounderUnitTranslationError: String {
    case missingCalibration = "Calibration required for unit translation"
    case missingSample = "Insufficient motion sample"
}

enum FounderUnits {
    /// Optional pixels-per-meter scale injected by calibration. When absent, UI will refuse conversion.
    static var pixelsPerMeter: Double?

    static func mph(fromPxPerSec px: Double?) -> Result<Double, FounderUnitTranslationError> {
        guard let px else { return .failure(.missingSample) }
        guard let pxPerMeter = pixelsPerMeter, pxPerMeter > 0 else { return .failure(.missingCalibration) }

        let metersPerSecond = px / pxPerMeter
        let mph = metersPerSecond * 2.23694
        return .success(mph)
    }

    static func yards(fromPixels px: Double?) -> Result<Double, FounderUnitTranslationError> {
        guard let px else { return .failure(.missingSample) }
        guard let pxPerMeter = pixelsPerMeter, pxPerMeter > 0 else { return .failure(.missingCalibration) }

        let meters = px / pxPerMeter
        let yards = meters * 1.09361
        return .success(yards)
    }
}

final class ShotStabilityIndexCalculator {
    private var speeds: [Double] = []
    private var angles: [Double] = []
    private var directions: [Double] = []
    private var confidences: [Float] = []
    private let window: Int

    init(window: Int = 10) {
        self.window = window
    }

    func push(speed: Double?, angle: Double?, direction: Double?, confidence: Float) -> Int {
        if let s = speed { speeds.append(s) }
        if let a = angle { angles.append(a) }
        if let d = direction { directions.append(d) }
        confidences.append(confidence)

        trim()
        return compute()
    }

    private func trim() {
        if speeds.count > window { speeds.removeFirst(speeds.count - window) }
        if angles.count > window { angles.removeFirst(angles.count - window) }
        if directions.count > window { directions.removeFirst(directions.count - window) }
        if confidences.count > window { confidences.removeFirst(confidences.count - window) }
    }

    private func score(from values: [Double]) -> Double {
        guard values.count >= 2 else { return 1.0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean != 0 else { return 1.0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let stdDev = sqrt(variance)
        let normalized = min(stdDev / abs(mean), 1.0)
        return max(0, 1.0 - normalized)
    }

    private func confidenceScore() -> Double {
        guard !confidences.isEmpty else { return 1.0 }
        let mean = confidences.reduce(0, +) / Float(confidences.count)
        return max(0, min(Double(mean) / 20.0, 1.0))
    }

    private func compute() -> Int {
        let speedScore = score(from: speeds)
        let angleScore = score(from: angles)
        let dirScore = score(from: directions)
        let confScore = confidenceScore()

        let composite = (speedScore + angleScore + dirScore + confScore) / 4.0
        return Int((composite * 100).rounded())
    }
}

final class FounderSessionManager {
    private var nextId = 1
    private let ssi = ShotStabilityIndexCalculator()

    private var lastLockedCenter: CGPoint?
    private var lastTimestamp: Double?
    private var armed = false
    private var lifecycleState: ShotLifecycleState = .idle

    private(set) var latestShot: ShotRecord?
    private(set) var history: [ShotRecord] = []

    var lifecycle: ShotLifecycleState { lifecycleState }

    func reset() {
        history.removeAll()
        latestShot = nil
        armed = false
        lastLockedCenter = nil
        lastTimestamp = nil
        lifecycleState = .idle
    }

    func handleFrame(_ telemetry: FounderFrameTelemetry) -> ShotEvent {
        defer { updateLiveState(telemetry) }

        updateLifecycleState(with: telemetry)

        guard telemetry.ballLocked else {
            if armed {
                let refusal = makeRefusal(reason: telemetry.mdgDecision?.reason ?? "unlock_before_motion")
                store(refusal)
                lifecycleState = .summary(refusal)
                return ShotEvent(shot: refusal, lifecycle: lifecycleState)
            }
            return ShotEvent(shot: nil, lifecycle: lifecycleState)
        }

        armed = true

        guard let center = telemetry.center else {
            return ShotEvent(shot: nil, lifecycle: lifecycleState)
        }

        if let previous = lastLockedCenter, let lastTs = lastTimestamp {
            let dt = max(telemetry.timestampSec - lastTs, 1.0 / 240.0)
            let dx = Double(center.x - previous.x)
            let dy = Double(center.y - previous.y)
            let motionPx = hypot(dx, dy) / dt
            let observedMotion = telemetry.mdgDecision?.vPxPerSec ?? motionPx

            let meetsMotionGate = observedMotion >= telemetry.motionGatePxPerSec

            if meetsMotionGate {
                let launchAngle = angleDegrees(y: -dy, x: dx)
                let direction = angleDegrees(y: 0, x: dx)
                let stability = ssi.push(speed: observedMotion,
                                         angle: launchAngle,
                                         direction: direction,
                                         confidence: telemetry.confidence)

                let record = ShotRecord(
                    id: nextId,
                    timestamp: Date(),
                    measured: ShotMeasuredData(
                        ballSpeedPxPerSec: observedMotion,
                        launchAngleDeg: launchAngle,
                        launchDirectionDeg: direction,
                        stabilityIndex: stability,
                        impact: .unknown,
                        pixelDisplacement: hypot(dx, dy),
                        frameIntervalSec: dt
                    ),
                    estimated: ShotEstimatedData(
                        carryDistance: nil,
                        apexHeight: nil,
                        dispersion: nil
                    ),
                    status: .measured,
                    refusalReasons: ["spin_unobserved"]
                )

                nextId += 1
                let capturedEvent = ShotEvent(shot: record, lifecycle: .captured(record))
                store(record)
                armed = false
                lifecycleState = .summary(record)
                return capturedEvent
            }
        }

        lastLockedCenter = center
        lastTimestamp = telemetry.timestampSec
        return ShotEvent(shot: nil, lifecycle: lifecycleState)
    }

    private func disarm() {
        armed = false
        lastLockedCenter = nil
        lastTimestamp = nil
    }

    private func makeRefusal(reason: String) -> ShotRecord {
        let stability = ssi.push(speed: nil, angle: nil, direction: nil, confidence: 0)
        disarm()
        let record = ShotRecord(
            id: nextId,
            timestamp: Date(),
            measured: nil,
            estimated: nil,
            status: .refused,
            refusalReasons: [reason, "spin_unobserved"]
        )
        nextId += 1
        _ = stability
        return record
    }

    private func store(_ record: ShotRecord) {
        latestShot = record
        history.append(record)
        if history.count > 10 { history.removeFirst(history.count - 10) }
    }

    private func updateLiveState(_ telemetry: FounderFrameTelemetry) {
        if !telemetry.ballLocked {
            lastLockedCenter = nil
            lastTimestamp = nil
        }
    }

    private func updateLifecycleState(with telemetry: FounderFrameTelemetry) {
        if telemetry.ballLocked {
            lifecycleState = .armed(confidence: telemetry.confidence)
        } else if case .summary = lifecycleState {
            // Preserve summary state until a new armed cycle begins
        } else {
            lifecycleState = .idle
        }
    }

    private func angleDegrees(y: Double, x: Double) -> Double {
        return atan2(y, x) * 180.0 / .pi
    }
}
