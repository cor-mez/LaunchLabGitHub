//
//  VisionPipeline.swift
//  LaunchLab
//
//  RS-first observability pipeline.
//  NO AUTHORITY.
//  NO LIFECYCLE.
//  Answers only: what did the sensor encode on this frame?
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
    // MARK: - Tunables (LOCKED FOR DIAGNOSIS)
    // -------------------------------------------------------------

    /// Minimum row coherence to consider RS localized
    private let minRowAdjCorrelation: Float = 0.55

    /// Maximum allowed flicker banding dominance
    private let maxBandingScore: Float = 8_000

    // -------------------------------------------------------------
    // MARK: - Reset
    // -------------------------------------------------------------

    func reset() {
        rsDetector.reset()
        refractoryGate.reset(reason: "pipeline_reset")
    }

    // -------------------------------------------------------------
    // MARK: - Frame Processing (OBSERVATIONAL ONLY)
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
        // 🔍 PER-FRAME OBSERVABILITY LOG (TRUTHFUL)
        // ---------------------------------------------------------

        Log.info(
            .shot,
            String(
                format:
                "RS_OBSERVED t=%.3f z=%.2f dz=%.2f rowCorr=%.2f band=%.0f impulse=%d reject=%@",
                timestamp,
                rs.zmax,
                rs.dz,
                rs.rowAdjCorrelation,
                rs.bandingScore,
                rs.isImpulse ? 1 : 0,
                rs.rejectionReason
            )
        )

        // ---------------------------------------------------------
        // RS STRUCTURE OBSERVABILITY (NO LATCHING)
        // ---------------------------------------------------------

        let rsStructureObservable =
            rs.isImpulse &&
            rs.rowAdjCorrelation >= minRowAdjCorrelation &&
            rs.bandingScore <= maxBandingScore &&
            refractoryGate.tryAcceptImpulse(timestamp: timestamp)

        if rsStructureObservable {
            Log.info(
                .shot,
                String(
                    format:
                    "RS_SIGNAL_OBSERVED t=%.3f rowCorr=%.2f band=%.0f",
                    timestamp,
                    rs.rowAdjCorrelation,
                    rs.bandingScore
                )
            )
        }

        // ---------------------------------------------------------
        // Refractory update (OBSERVATIONAL SUPPRESSION ONLY)
        // ---------------------------------------------------------

        refractoryGate.update(
            timestamp: timestamp,
            sceneIsQuiet: !rs.isImpulse
        )

        if !refractoryGate.isLocked {
            // No state to reset; log only for visibility
            Log.info(.shot, "RS_REFRACTORY_RELEASED t=\(String(format: "%.3f", timestamp))")
        }

        // ---------------------------------------------------------
        // Emit frame data (NO AUTHORITY FIELDS SET)
        // ---------------------------------------------------------

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
