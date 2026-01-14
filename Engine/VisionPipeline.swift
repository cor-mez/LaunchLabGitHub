//
//  VisionPipeline.swift
//  LaunchLab
//
//  V1.7: Centroid-authoritative pipeline with
//  RS emission gate + ShotLock + Lifecycle Deadman Guard
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

    private var frameIndex: Int = 0
    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0
    private var lastIntrinsics: (Float, Float, Float, Float)?

    // Intent + centroid authority
    private var intentState: IntentState = .idle
    private var centroidHistory: [CGPoint] = []

    // Shot authority
    private var shotLock = ShotLock()

    // Lifecycle + safety
    private var lifecycleState: ShotLifecycleState = .idle
    private let deadman = LifecycleDeadmanGuard()

    // ---------------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    private let motionWindow: Int = 10
    private let minCentroidSpeed: CGFloat = 1.5
    private let minIntentFrames: Int = 3
    private let decayFrames: Int = 6

    // RS temporal alignment window
    private let rsAlignmentWindow: Double = 0.030 // 30 ms

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        frameIndex = 0
        lastFrameWidth = 0
        lastFrameHeight = 0
        lastIntrinsics = nil

        centroidHistory.removeAll()
        intentState = .idle
        lifecycleState = .idle

        shotLock.reset()
        deadman.reset()
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

        let intrTuple = (
            intrinsics.fx,
            intrinsics.fy,
            intrinsics.cx,
            intrinsics.cy
        )

        // Reset if geometry changes
        if lastFrameWidth != 0 {
            if width != lastFrameWidth ||
               height != lastFrameHeight ||
               lastIntrinsics.map({ $0 != intrTuple }) ?? false {
                reset()
            }
        }

        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsics = intrTuple
        frameIndex &+= 1

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
        // Marker Detection (Authoritative)
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
            shotLock.reset()
        }

        if centroidHistory.count > motionWindow {
            centroidHistory.removeFirst()
        }

        // -----------------------------------------------------------------
        // Intent State Evaluation
        // -----------------------------------------------------------------

        evaluateIntentState(at: timestamp)

        // -----------------------------------------------------------------
        // Lifecycle Deadman Guard (MECHANICAL SAFETY)
        // -----------------------------------------------------------------

        let deadmanOutcome = deadman.update(
            lifecycleState: lifecycleState,
            timestamp: timestamp
        )

        switch deadmanOutcome {

        case .forceRefuse(let reason):
            print("[DEADMAN_REFUSE] \(reason)")
            lifecycleState = .idle
            shotLock.reset()
            deadman.reset()

        case .forceReset(let reason):
            print("[DEADMAN_RESET] \(reason)")
            reset()

        case .none:
            break
        }

        // -----------------------------------------------------------------
        // RS Emission + Shot Lock (unchanged authority)
        // -----------------------------------------------------------------

        if isRSEmissionAuthorized(at: timestamp),
           !shotLock.isLocked {

            _ = rsDetector.analyze(
                pixelBuffer: pixelBuffer,
                roi: roiRect,
                timestamp: timestamp
            )

            if shotLock.tryLock(
                timestamp: timestamp,
                zmax: 0.0   // RS remains non-authoritative
            ) {
                print(String(format: "[SHOT_COMMIT] t=%.4f", timestamp))
                lifecycleState = .idle
                deadman.reset()
            }
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
    // MARK: - Intent State Machine
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
                lifecycleState = .preImpact
            }

        case .candidate:
            if movingFrames >= minIntentFrames {
                intentState = .active(startTime: timestamp)
                lifecycleState = .impactObserved
            } else {
                intentState = .idle
                lifecycleState = .idle
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
                lifecycleState = .idle
                shotLock.reset()
                deadman.reset()
                rsDetector.reset()
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - RS Emission Authorization
    // ---------------------------------------------------------------------

    private func isRSEmissionAuthorized(at timestamp: Double) -> Bool {

        switch intentState {

        case .active(let startTime):
            return timestamp >= startTime

        case .decay(let startTime):
            return (timestamp - startTime) <= rsAlignmentWindow

        default:
            return false
        }
    }
}
