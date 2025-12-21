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
    let sceneScale: SceneScale
}

enum FounderPresentationMode {
    case frameDebug
    case shotSummary
}

struct SceneScale {
    let pixelsPerMeter: Double
}

struct ShotSummary {
    let ballSpeed: Double?
    let launchAngle: Double?
    let direction: Double?
    let shotStabilityIndex: Int
    let impactDetected: Bool
    let refusalReason: String?

    let carryDistanceYards: Double?
    let apexHeightYards: Double?
    let dispersionYards: Double?
}

struct UnitConverter {
    static func pxPerSecToMPH(_ pxPerSec: Double, scale: SceneScale) -> Double {
        let metersPerSec = pxPerSec / scale.pixelsPerMeter
        return metersPerSec * 2.23694
    }

    static func metersToYards(_ meters: Double) -> Double {
        return meters * 1.09361
    }
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

    private(set) var latestShot: ShotRecord?
    private(set) var history: [ShotRecord] = []

    func reset() {
        history.removeAll()
        latestShot = nil
        armed = false
        lastLockedCenter = nil
        lastTimestamp = nil
    }

    func handleFrame(_ telemetry: FounderFrameTelemetry) -> ShotRecord? {
        defer { updateLiveState(telemetry) }

        guard telemetry.ballLocked else {
            if armed {
                let refusal = makeRefusal(reason: telemetry.mdgDecision?.reason ?? "unlock_before_motion")
                store(refusal)
                return refusal
            }
            return nil
        }

        armed = true

        guard let center = telemetry.center else {
            return nil
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
                        impact: .unknown
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
                store(record)
                armed = false
                return record
            }
        }

        lastLockedCenter = center
        lastTimestamp = telemetry.timestampSec
        return nil
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

    private func angleDegrees(y: Double, x: Double) -> Double {
        return atan2(y, x) * 180.0 / .pi
    }
}
