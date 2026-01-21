//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Rolling-Shutter Measurement Harness (V6)
//
//  ROLE (STRICT):
//  - OBSERVATION ONLY
//  - NO authority
//  - NO lifecycle decisions
//  - NO latching
//  - Produces explicit facts for ShotLifecycleController
//

import CoreMedia
import CoreVideo
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    // -----------------------------------------------------------
    // MARK: - Observers (PURE OBSERVATION)
    // -----------------------------------------------------------

    private let detector = MetalDetector.shared
    private let rsProbe = RollingShutterProbe()
    private let rsFilter = RSGatedPointFilter()
    private let stats = RollingShutterSessionStats()

    private let cadenceEstimator = CadenceEstimator()
    private let impulseObserver = ImpactImpulseAuthority()

    // -----------------------------------------------------------
    // MARK: - Authority Spine (SINGULAR, CALLED ONLY)
    // -----------------------------------------------------------

    private let shotAuthority = ShotLifecycleController()

    // -----------------------------------------------------------
    // MARK: - Debug / Overlay (READ-ONLY)
    // -----------------------------------------------------------

    private(set) var debugROI: CGRect = .zero
    private(set) var debugFullSize: CGSize = .zero

    // -----------------------------------------------------------
    // MARK: - Harness Controls
    // -----------------------------------------------------------

    private let detectionInterval = 2
    private var frameIndex = 0

    private init() {}

    // -----------------------------------------------------------
    // MARK: - Frame Processing
    // -----------------------------------------------------------

    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {

        let tSec = CMTimeGetSeconds(timestamp)

        // -------------------------------------------------------
        // Cadence observability (FACT)
        // -------------------------------------------------------

        cadenceEstimator.push(timestamp: tSec)
        let captureValid = cadenceEstimator.estimatedFPS >= 90

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard w > 64, h > 64 else { return }

        let roi = CGRect(
            x: CGFloat(w) * 0.5 - 120,
            y: CGFloat(h) * 0.5 - 120,
            width: 200,
            height: 200
        ).integral

        debugROI = roi
        debugFullSize = CGSize(width: w, height: h)

        // -------------------------------------------------------
        // GPU → FAST9 → RS OBSERVATION
        // -------------------------------------------------------

        detector.prepareFrameY(
            pixelBuffer,
            roi: roi,
            srScale: 1.0
        ) { [weak self] in
            guard let self else { return }

            self.detector.gpuFast9ScoredCornersY { metalPoints in

                let rawPoints: [CGPoint] = metalPoints.map { $0.point }
                let filtPoints = self.rsFilter.filter(points: rawPoints)

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

                    // Baseline accumulation (truth-only, no decisions)
                    self.stats.addBaseline(sample)

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
                // Impulse derivative (FACT ONLY)
                // ---------------------------------------------------

                let impulseDelta =
                    self.impulseObserver.observe(speedPxPerSec: 0)?
                        .deltaSpeedPxPerSec ?? 0

                let impactObserved = impulseDelta > 900

                // ---------------------------------------------------
                // HARD OBSERVABILITY → EXPLICIT REFUSAL
                // ---------------------------------------------------

                let refusalReason: RefusalReason? = {
                    if !captureValid {
                        Log.info(.shot, "OBSERVABILITY_REFUSE invalid_capture_cadence")
                        return .insufficientConfidence
                    }
                    if !rsObservable {
                        Log.info(.shot, "OBSERVABILITY_REFUSE rs_not_observable")
                        return .insufficientConfidence
                    }
                    return nil
                }()

                // ---------------------------------------------------
                // AUTHORITY INPUT (SINGULAR SPINE)
                // ---------------------------------------------------

                let input = ShotLifecycleInput(
                    timestampSec: tSec,
                    captureValid: captureValid,
                    rsObservable: rsObservable,
                    eligibleForShot: false,          // not wired yet
                    impactObserved: impactObserved,
                    postImpactObserved: false,       // not wired yet
                    confirmedByUpstream: false,      // frozen in V1
                    refusalReason: refusalReason
                )

                Task {
                    _ = await self.shotAuthority.update(input)
                }            }
        }
    }
}
