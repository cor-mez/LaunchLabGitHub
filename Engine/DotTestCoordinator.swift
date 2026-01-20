//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Rolling-Shutter Measurement Harness v5
//
//  OBSERVATION + WIRING ONLY
//  - No detection
//  - No authority
//  - Feeds ShotLifecycleController with explicit evidence
//

import CoreMedia
import CoreVideo
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    // -----------------------------------------------------------
    // Core Observers
    // -----------------------------------------------------------

    private let detector = MetalDetector.shared
    private let rsProbe = RollingShutterProbe()
    private let rsFilter = RSGatedPointFilter()
    private let stats = RollingShutterSessionStats()

    // -----------------------------------------------------------
    // Authority Spine (SINGULAR)
    // -----------------------------------------------------------

    private let shotAuthority = ShotLifecycleController()
    private let eligibilityGate = ShotAuthorityGate()
    private let impulseObserver = ImpactImpulseAuthority()

    // -----------------------------------------------------------
    // Cadence Estimation (OBSERVABILITY)
    // -----------------------------------------------------------

    private let cadenceEstimator = CadenceEstimator()

    // -----------------------------------------------------------
    // Overlay / Debug (NON-AUTHORITATIVE)
    // -----------------------------------------------------------

    private(set) var debugROI: CGRect = .zero
    private(set) var debugFullSize: CGSize = .zero
    private(set) var debugBallLocked: Bool = false
    private(set) var debugConfidence: Float = 0

    // -----------------------------------------------------------
    // Harness Controls
    // -----------------------------------------------------------

    var baselineModeEnabled: Bool = true
    private let minBaselineFrames: Int = 60

    private let detectionInterval = 2
    private var frameIndex = 0
    private var framesSinceIdle: Int = 0

    private init() {}

    // -----------------------------------------------------------
    // Baseline Reset
    // -----------------------------------------------------------

    func resetBaseline() {
        stats.resetBaseline()
        baselineModeEnabled = true
        Log.info(.detection, "rs baseline reset")
    }

    // -----------------------------------------------------------
    // Frame Processing (OBSERVATION → AUTHORITY INPUT)
    // -----------------------------------------------------------

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        let tSec = CMTimeGetSeconds(timestamp)

        // Cadence observability
        cadenceEstimator.push(timestamp: tSec)

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 64, h > 64 else { return }

        let roi = CGRect(
            x: CGFloat(w) * 0.5 - 120,
            y: CGFloat(h) * 0.5 - 120,
            width: 200,
            height: 200
        ).integral

        debugROI = roi
        debugFullSize = CGSize(width: w, height: h)
        debugBallLocked = false
        debugConfidence = 0

        detector.prepareFrameY(
            pb,
            roi: roi,
            srScale: 1.0
        ) { [weak self] in
            guard let self else { return }

            self.detector.gpuFast9ScoredCornersY { metalPoints in

                let rawPoints: [CGPoint] = metalPoints.map { $0.point }
                let filtPoints: [CGPoint] = self.rsFilter.filter(points: rawPoints)

                // ---------------------------------------------------
                // RS OBSERVATION
                // ---------------------------------------------------

                let rsObservation = self.rsProbe.evaluate(
                    points: filtPoints,
                    roi: roi
                )

                let rsObservable = (rsObservation != nil)

                if !rsObservable {
                    Log.info(
                        .detection,
                        "rs_no_signal raw=\(rawPoints.count) filt=\(filtPoints.count)"
                    )
                }

                // ---------------------------------------------------
                // Baseline + Z-score (OBSERVATIONAL ONLY)
                // ---------------------------------------------------

                if let rs = rsObservation {

                    let sample = RSFeatureSample(
                        slope: rs.rowSlope,
                        r2: rs.rowSlopeR2,
                        nonu: rs.rowNonuniformity,
                        lw: rs.streakLW,
                        edge: rs.edgeStraightness,
                        rawCount: Double(rawPoints.count),
                        filtCount: Double(filtPoints.count)
                    )

                    if self.baselineModeEnabled {
                        self.stats.addBaseline(sample)

                        if self.stats.hasBaseline(minCount: self.minBaselineFrames) {
                            self.baselineModeEnabled = false
                            Log.info(
                                .detection,
                                "rs_baseline_locked | \(self.stats.baselineSummary())"
                            )
                        }
                    }

                    if let z = self.stats.zScores(for: sample) {
                        Log.info(
                            .detection,
                            String(
                                format: "rs_zmax=%.2f raw=%d filt=%d",
                                z.maxAbs,
                                Int(sample.rawCount),
                                Int(sample.filtCount)
                            )
                        )
                    }
                }

                // ---------------------------------------------------
                // MOTION / ELIGIBILITY (STUB SIGNALS)
                // ---------------------------------------------------

                let lifecycleState: ShotAuthorityLifecycleState =
                    (self.shotAuthority.state == .idle) ? .idle : .inProgress

                let eligibilityDecision = self.eligibilityGate.update(
                    ShotAuthorityGateInput(
                        timestampSec: tSec,
                        ballLockConfidence: self.debugConfidence,
                        instantaneousPxPerSec: 0, // stubbed
                        motionPhase: .idle,       // stubbed
                        framesSinceIdle: self.framesSinceIdle,
                        lifecycleState: lifecycleState
                    )
                )

                let eligibleForShot = (eligibilityDecision == .eligible)

                if eligibleForShot {
                    self.impulseObserver.armObservationWindow()
                }

                // ---------------------------------------------------
                // HARD OBSERVABILITY GATES
                // ---------------------------------------------------

                let captureValid = self.cadenceEstimator.estimatedFPS >= 90

                // We cannot construct RefusalReason here.
                // Use an existing, controlled refusal reason and log specifics separately.
                let refusalReason: RefusalReason? = {
                    if !captureValid {
                        Log.info(.shot, "OBSERVABILITY_REFUSE cause=invalid_capture_cadence fps=\(String(format: "%.1f", self.cadenceEstimator.estimatedFPS))")
                        return .insufficientConfidence
                    }
                    if !rsObservable {
                        Log.info(.shot, "OBSERVABILITY_REFUSE cause=rs_not_observable")
                        return .insufficientConfidence
                    }
                    return nil
                }()

                // ---------------------------------------------------
                // AUTHORITY INPUT (REFUSAL-FIRST, FAIL CLOSED)
                // ---------------------------------------------------

                let authorityInput = ShotLifecycleInput(
                    timestampSec: tSec,
                    captureValid: captureValid,
                    rsObservable: rsObservable,
                    eligibleForShot: eligibleForShot,
                    confirmedByUpstream: false, // acceptance frozen
                    ballLockConfidence: self.debugConfidence,
                    motionDensityPhase: .idle,
                    ballSpeedPxPerSec: nil,
                    refusalReason: refusalReason
                )

                _ = self.shotAuthority.update(authorityInput)
            }
        }
    }
}
