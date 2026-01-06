//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Rolling-Shutter Measurement Harness v4
//
//  NO DETECTION. NO AUTHORITY.
//  RS OBSERVABILITY ONLY.
//

import CoreMedia
import CoreVideo
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    private let detector = MetalDetector.shared
    private let rsProbe = RollingShutterProbe()
    private let rsFilter = RSGatedPointFilter()
    private let stats = RollingShutterSessionStats()

    // Overlay only
    private(set) var debugROI: CGRect = .zero
    private(set) var debugFullSize: CGSize = .zero
    private(set) var debugBallLocked: Bool = false
    private(set) var debugConfidence: Float = 0

    // Harness controls
    var baselineModeEnabled: Bool = true
    private let minBaselineFrames: Int = 60
    private let eventZThreshold: Double = 4.0

    private let detectionInterval = 2
    private var frameIndex = 0

    private init() {}

    func resetBaseline() {
        stats.resetBaseline()
        baselineModeEnabled = true
        Log.info(.detection, "rs baseline reset")
    }

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 64, h > 64 else { return }

        let roi = CGRect(
            x: CGFloat(w) * 0.5 - 120,
            y: CGFloat(h) * 0.5 - 120,
            width: 240,
            height: 240
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

                // Metal → CGPoint (ONLY type boundary)
                let rawPoints: [CGPoint] = metalPoints.map { $0.point }

                // RS geometric filter
                let filtPoints: [CGPoint] = self.rsFilter.filter(points: rawPoints)

                guard let rs = self.rsProbe.evaluate(
                    points: filtPoints,
                    roi: roi
                ) else {
                    Log.info(
                        .detection,
                        "rs=no_signal raw=\(rawPoints.count) filt=\(filtPoints.count)"
                    )
                    return
                }

                let sample = RSFeatureSample(
                    slope: rs.rowSlope,
                    r2: rs.rowSlopeR2,
                    nonu: rs.rowNonuniformity,
                    lw: rs.streakLW,
                    edge: rs.edgeStraightness,
                    rawCount: Double(rawPoints.count),
                    filtCount: Double(filtPoints.count)
                )

                // Baseline collection
                if self.baselineModeEnabled {
                    self.stats.addBaseline(sample)

                    if self.stats.hasBaseline(minCount: self.minBaselineFrames) {
                        self.baselineModeEnabled = false
                        Log.info(
                            .detection,
                            "rs baseline locked | \(self.stats.baselineSummary())"
                        )
                    }
                }

                // Z-score logging
                if let z = self.stats.zScores(for: sample) {

                    Log.info(
                        .detection,
                        String(
                            format:
                            "rs slope=%.4f r2=%.2f nonu=%.2f lw=%.2f edge=%.2f raw=%d filt=%d | zmax=%.2f",
                            sample.slope,
                            sample.r2,
                            sample.nonu,
                            sample.lw,
                            sample.edge,
                            Int(sample.rawCount),
                            Int(sample.filtCount),
                            z.maxAbs
                        )
                    )

                    if z.maxAbs >= self.eventZThreshold {
                        Log.info(
                            .detection,
                            String(
                                format:
                                "rs EVENT_CAND zmax=%.2f raw=%d filt=%d",
                                z.maxAbs,
                                Int(sample.rawCount),
                                Int(sample.filtCount)
                            )
                        )
                    }

                } else {
                    Log.info(
                        .detection,
                        String(
                            format:
                            "rs slope=%.4f r2=%.2f nonu=%.2f lw=%.2f edge=%.2f raw=%d filt=%d | baseline n=%d",
                            sample.slope,
                            sample.r2,
                            sample.nonu,
                            sample.lw,
                            sample.edge,
                            Int(sample.rawCount),
                            Int(sample.filtCount),
                            self.stats.baselineCount
                        )
                    )
                }
            }
        }
    }
}
