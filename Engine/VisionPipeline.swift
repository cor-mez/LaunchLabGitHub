//
//  VisionPipeline.swift
//  LaunchLab
//
//  V1.8: RS-impulse-first sensing pipeline
//  Intent = arming only
//  RS impulse = shot detection
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

final class VisionPipeline {

    // ---------------------------------------------------------------------
    // MARK: - Detectors
    // ---------------------------------------------------------------------

    private let markerDetector = MarkerDetectorV1()
    private let rsDetector = RollingShutterDetectorV1()

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    private var intentState: IntentState = .idle
    private var centroidHistory: [CGPoint] = []

    // ---------------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    private let motionWindow: Int = 10
    private let minCentroidSpeed: CGFloat = 1.5
    private let minIntentFrames: Int = 3
    private let decayFrames: Int = 6

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        centroidHistory.removeAll()
        intentState = .idle
        rsDetector.reset()
    }

    // ---------------------------------------------------------------------
    // MARK: - Frame Processing
    // ---------------------------------------------------------------------

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // -----------------------------------------------------------------
        // ROI (LOCKED)
        // -----------------------------------------------------------------

        let roiSide: CGFloat = 200.0
        let roiRect = CGRect(
            x: CGFloat(width) * 0.5 - roiSide * 0.5,
            y: CGFloat(height) * 0.5 - roiSide * 0.5,
            width: roiSide,
            height: roiSide
        )

        // -----------------------------------------------------------------
        // Marker Presence (NOT motion authority)
        // -----------------------------------------------------------------

        let marker = markerDetector.detect(
            pixelBuffer: pixelBuffer,
            roi: roiRect
        )

        if let m = marker {
            centroidHistory.append(m.center)
        } else {
            centroidHistory.removeAll()
            intentState = .idle
            rsDetector.disarm(reason: "marker_lost")
        }

        if centroidHistory.count > motionWindow {
            centroidHistory.removeFirst()
        }

        // -----------------------------------------------------------------
        // Intent Evaluation (ARMING ONLY)
        // -----------------------------------------------------------------

        evaluateIntentState(at: timestamp)

        // Arm RS detector only when intent is active or decaying
        switch intentState {
        case .active, .decay:
            rsDetector.arm()
        default:
            break
        }

        // -----------------------------------------------------------------
        // RS Impulse Detection (SINGLE-SHOT)
        // -----------------------------------------------------------------

        let rsResult = rsDetector.analyze(
            pixelBuffer: pixelBuffer,
            roi: roiRect,
            timestamp: timestamp
        )

        if rsResult.isImpulse {
            Log.info(
                .shot,
                String(
                    format: "shot_detected t=%.3f zmax=%.2f",
                    timestamp,
                    Double(rsResult.zmax)
                )
            )
        }

        // -----------------------------------------------------------------
        // Frame Output (unchanged)
        // -----------------------------------------------------------------

        return VisionFrameData(
            rawDetectionPoints: [],
            dots: [],
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
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

    // ---------------------------------------------------------------------
    // MARK: - Intent State Machine (ARMING ONLY)
    // ---------------------------------------------------------------------

    private func evaluateIntentState(at timestamp: Double) {

        guard centroidHistory.count >= 2 else {
            intentState = .idle
            return
        }

        var speeds: [CGFloat] = []

        for i in 1..<centroidHistory.count {
            let dx = centroidHistory[i].x - centroidHistory[i - 1].x
            let dy = centroidHistory[i].y - centroidHistory[i - 1].y
            speeds.append(hypot(dx, dy))
        }

        let movingFrames = speeds.filter { $0 > minCentroidSpeed }.count

        switch intentState {

        case .idle:
            if movingFrames >= minIntentFrames {
                intentState = .candidate(startTime: timestamp)
            }

        case .candidate:
            if movingFrames >= minIntentFrames {
                intentState = .active(startTime: timestamp)
            } else {
                intentState = .idle
            }

        case .active:
            if movingFrames == 0 {
                intentState = .decay(startTime: timestamp)
            }

        case .decay:
            if movingFrames > 0 {
                intentState = .active(startTime: timestamp)
            } else if centroidHistory.count >= decayFrames {
                intentState = .idle
                rsDetector.disarm(reason: "intent_decay_complete")
            }
        }
    }
}
