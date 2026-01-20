//
//  VisionPipeline.swift
//  LaunchLab
//
//  RS-first observability pipeline.
//  No ball assumptions. No marker dependency.
//  Answers only: did the sensor see a coherent RS event?
//

import Foundation
import CoreGraphics
import CoreVideo

final class VisionPipeline {

    // -------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------

    private let rsDetector = RollingShutterDetectorV2()
    private let refractoryGate = RefractoryGate()

    // -------------------------------------------------------------
    // MARK: - Phase
    // -------------------------------------------------------------

    private enum Phase: CustomStringConvertible {
        case idle
        case rsCandidate(timestamp: Double)
        case confirmed(timestamp: Double)

        var description: String {
            switch self {
            case .idle: return "idle"
            case .rsCandidate: return "rsCandidate"
            case .confirmed: return "confirmed"
            }
        }
    }

    private var phase: Phase = .idle

    // -------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR DIAGNOSIS)
    // -------------------------------------------------------------

    /// Minimum row coherence to consider RS localized
    private let minRowAdjCorrelation: Float = 0.55

    /// Maximum allowed flicker banding dominance
    private let maxBandingScore: Float = 8_000

    /// Refractory window controlled elsewhere
    /// No time decay logic here

    // -------------------------------------------------------------
    // MARK: - Reset
    // -------------------------------------------------------------

    func reset() {
        phase = .idle
        rsDetector.reset()
        refractoryGate.reset(reason: "pipeline_reset")
    }

    // -------------------------------------------------------------
    // MARK: - Frame Processing
    // -------------------------------------------------------------

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // ROI intentionally large and permissive
        let roiRect = CGRect(
            x: w * 0.15,
            y: h * 0.25,
            width: w * 0.70,
            height: h * 0.50
        )

        let rs = rsDetector.analyze(
            pixelBuffer: pixelBuffer,
            roi: roiRect,
            timestamp: timestamp
        )

        // ---------------------------------------------------------
        // 🔍 PER-FRAME OBSERVABILITY LOG (ALWAYS ON)
        // ---------------------------------------------------------

        Log.info(
            .shot,
            String(
                format:
                "RS_FRAME t=%.3f phase=%@ z=%.2f dz=%.2f rowCorr=%.2f band=%.0f impulse=%d reject=%@",
                timestamp,
                phase.description,
                rs.zmax,
                rs.dz,
                rs.rowAdjCorrelation,
                rs.bandingScore,
                rs.isImpulse ? 1 : 0,
                rs.rejectionReason
            )
        )

        // ---------------------------------------------------------
        // Phase Machine
        // ---------------------------------------------------------

        switch phase {

        case .idle:

            // Accept ONLY if RS structure passes observability gates
            if rs.isImpulse,
               rs.rowAdjCorrelation >= minRowAdjCorrelation,
               rs.bandingScore <= maxBandingScore,
               refractoryGate.tryAcceptImpulse(timestamp: timestamp) {

                Log.info(
                    .shot,
                    String(
                        format:
                        "RS_CANDIDATE_ACCEPTED t=%.3f rowCorr=%.2f band=%.0f",
                        timestamp,
                        rs.rowAdjCorrelation,
                        rs.bandingScore
                    )
                )

                phase = .rsCandidate(timestamp: timestamp)
            }

        case .rsCandidate(let t0):

            // One-frame confirmation only — no emergence logic
            // We are confirming *sensor structure*, not object tracking

            if rs.rowAdjCorrelation >= minRowAdjCorrelation &&
               rs.bandingScore <= maxBandingScore {

                Log.info(
                    .shot,
                    String(format: "RS_EVENT_CONFIRMED t=%.3f", t0)
                )

                phase = .confirmed(timestamp: t0)
            } else {
                Log.info(
                    .shot,
                    String(
                        format:
                        "RS_EVENT_REJECTED t=%.3f reason=rowCorr=%.2f band=%.0f",
                        t0,
                        rs.rowAdjCorrelation,
                        rs.bandingScore
                    )
                )
                phase = .idle
            }

        case .confirmed:
            // Hold until refractory releases
            break
        }

        // ---------------------------------------------------------
        // Refractory update (no silent phase reset)
        // ---------------------------------------------------------

        refractoryGate.update(
            timestamp: timestamp,
            sceneIsQuiet: !rs.isImpulse
        )

        if !refractoryGate.isLocked {
            if case .idle = phase {
                // already idle, no-op
            } else {
                Log.info(.shot, "PHASE → idle (refractory released)")
                phase = .idle
            }
        }

        return VisionFrameData(
            rawDetectionPoints: [],
            dots: [],
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: Int(w),
            height: Int(h),
            intrinsics: intrinsics,
            trackingState: .initial,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            residuals: nil,
            flowVectors: []
        )
    }
}
