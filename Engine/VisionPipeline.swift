//
//  VisionPipeline.swift
//  LaunchLab
//
//  Path A — RS derivative impulse → ball emergence
//  FULL OBSERVABILITY BUILD
//

import Foundation
import CoreGraphics
import CoreVideo

final class VisionPipeline {

    private let markerDetector = MarkerDetectorV1()
    private let rsDetector = RollingShutterDetectorV1()
    private let refractoryGate = RefractoryGate()

    // -------------------------------------------------------------
    // MARK: - Phase
    // -------------------------------------------------------------

    private enum Phase: CustomStringConvertible {
        case idle
        case impulseDetected(at: Double)
        case awaitingEmergence(start: Double)
        case confirmed

        var description: String {
            switch self {
            case .idle: return "idle"
            case .impulseDetected: return "impulseDetected"
            case .awaitingEmergence: return "awaitingEmergence"
            case .confirmed: return "confirmed"
            }
        }
    }

    private var phase: Phase = .idle
    private var lastBallCentroid: CGPoint?
    private var emergenceFrames: Int = 0

    // -------------------------------------------------------------
    // MARK: - Tunables (LOCKED)
    // -------------------------------------------------------------

    private let emergenceWindowSec: Double = 0.040
    private let minEmergenceFrames: Int = 2
    private let minBallMotionPx: CGFloat = 3.0

    // -------------------------------------------------------------
    // MARK: - Reset
    // -------------------------------------------------------------

    func reset() {
        phase = .idle
        lastBallCentroid = nil
        emergenceFrames = 0
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

        let roiRect = CGRect(
            x: w * 0.20,
            y: h * 0.35,
            width: w * 0.60,
            height: h * 0.45
        )

        let marker = markerDetector.detect(
            pixelBuffer: pixelBuffer,
            roi: roiRect
        )

        let rs = rsDetector.analyze(
            pixelBuffer: pixelBuffer,
            roi: roiRect,
            timestamp: timestamp
        )

        // ---------------------------------------------------------
        // 🔍 PER-FRAME RS SNAPSHOT (UNCONDITIONAL)
        // ---------------------------------------------------------

        Log.info(
            .shot,
            String(
                format:
                "RS_FRAME t=%.3f phase=%@ z=%.2f dz=%.2f impulse=%d reject=%@",
                timestamp,
                phase.description,
                rs.zmax,
                rs.dz,
                rs.isImpulse ? 1 : 0,
                rs.rejectionReason
            )
        )

        // ---------------------------------------------------------
        // Phase Machine (Path A)
        // ---------------------------------------------------------

        switch phase {

        case .idle:
            if rs.isImpulse,
               refractoryGate.tryAcceptImpulse(timestamp: timestamp) {

                Log.info(
                    .shot,
                    String(
                        format: "IMPULSE_ACCEPTED t=%.3f z=%.2f dz=%.2f",
                        timestamp, rs.zmax, rs.dz
                    )
                )

                phase = .impulseDetected(at: timestamp)
            }

        case .impulseDetected(let t0):
            phase = .awaitingEmergence(start: t0)
            emergenceFrames = 0
            lastBallCentroid = nil
            Log.info(.shot, "PHASE → awaitingEmergence")

        case .awaitingEmergence(let start):

            if timestamp - start > emergenceWindowSec {
                Log.info(.shot, "GHOST_REJECT reason=no_ball_emergence")
                phase = .confirmed
                break
            }

            if let m = marker {
                if let last = lastBallCentroid {
                    let d = hypot(m.center.x - last.x,
                                  m.center.y - last.y)
                    if d >= minBallMotionPx {
                        emergenceFrames += 1
                        Log.info(
                            .shot,
                            String(format: "BALL_MOTION d=%.2f frames=%d",
                                   d, emergenceFrames)
                        )
                    }
                }
                lastBallCentroid = m.center
            }

            if emergenceFrames >= minEmergenceFrames {
                Log.info(.shot, "SHOT_CONFIRMED")
                phase = .confirmed
            }

        case .confirmed:
            break
        }

        // ---------------------------------------------------------
        // Refractory update (NO phase reset here)
        // ---------------------------------------------------------

        refractoryGate.update(
            timestamp: timestamp,
            sceneIsQuiet: marker == nil && !rs.isImpulse
        )

        // Only reset AFTER terminal phase + refractory released
        if case .confirmed = phase, !refractoryGate.isLocked {
            Log.info(.shot, "PHASE → idle (refractory released)")
            phase = .idle
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
