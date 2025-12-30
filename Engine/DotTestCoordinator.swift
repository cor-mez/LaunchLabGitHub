//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Central engine coordinator (V1)
//  Motion-first shot detection, no HUDs.
//

import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import Metal

@MainActor
final class DotTestCoordinator {
    
    static let shared = DotTestCoordinator()
    
    let mode      = DotTestMode.shared
    let detector  = MetalDetector.shared
    let ballLock  = BallLockV0()
    let ballSpeedTracker = BallSpeedTracker()
    private let shotLifecycle = ShotLifecycleController()
    
    weak var previewView: FounderPreviewView?
    weak var founderDelegate: FounderTelemetryObserver?
    
    private var frameIndex: Int = 0
    private let detectionInterval: Int = 3
    private let rawMotionLogger = RawMotionLogger()
    // MARK: - Shot Authority

    private let authorityGate = ShotAuthorityGate()

    private var authorityIdleFrames: Int = 0
    private var lastAuthoritativeShotTimestampSec: Double? = nil

    // Used to emit approach → impact → separation phases without inventing new sensors
    private var wasMovingLastTick: Bool = false
    
    var lastROI: CGRect = .zero
    var lastFull: CGSize = .zero
    
    private init() {}
    
    // MARK: - Frame Entry
    
    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {
        
        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }
        guard mode.isArmedForDetection else { return }
        
        let t = CMTimeGetSeconds(timestamp)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }
        
        lastFull = CGSize(width: w, height: h)
        
        let roi = CGRect(
            x: lastFull.width * 0.5 - 50,
            y: lastFull.height * 0.5 - 50,
            width: 100,
            height: 100
        ).integral
        
        lastROI = roi
        
        detectGPU(pb: pb, roi: roi, timestampSec: t)
    }
    
    // MARK: - GPU Detection
    
    private func detectGPU(
        pb: CVPixelBuffer,
        roi: CGRect,
        timestampSec: Double
    ) {
        
        detector.prepareFrameY(
            pb,
            roi: roi,
            srScale: mode.srScale
        )
        
        let scored = detector.gpuFast9ScoredCornersY()
        let points = scored.map { $0.point }
        
        var confidence: Float = 0
        var center: CGPoint? = nil
        
        if let cluster = ballLock.findBallCluster(from: points) {
            
            confidence = Float(cluster.count)
            center = cluster.center
            
            // --- speed sampling (observation only) ---
            ballSpeedTracker.ingest(
                position: cluster.center,
                timestampSec: timestampSec
            )
            
            rawMotionLogger.log(
                timestampSec: timestampSec,
                center: cluster.center,
                clusterCount: cluster.count
            )
            
        } else {
            
            rawMotionLogger.logUnlocked(timestampSec: timestampSec)
            ballSpeedTracker.reset()
        }
        
        // --- compute instantaneous speed (no decisions here) ---
        
        let speedSample = ballSpeedTracker.compute(
            pixelsPerMeter: Double(max(lastFull.width, lastFull.height))
        )
        
        // Derive motion phase safely
        let motionPhase: MotionDensityPhase
        if let pxPerSec = speedSample?.pxPerSec, pxPerSec > 0 {
            motionPhase = .impact
        } else {
            motionPhase = .idle
        }
        
        // Define lockedNow explicitly
        let lockedNow: Bool = confidence > 0
        
        // Build lifecycle input (no interpretation)
        let input = ShotLifecycleInput(
            timestampSec: timestampSec,
            ballLockConfidence: confidence,
            motionDensityPhase: motionPhase,
            ballSpeedPxPerSec: speedSample?.pxPerSec,
            refusalReason: nil
        )
        
        // --- lifecycle update ---
        if let record = shotLifecycle.update(input) {

            ballSpeedTracker.reset()

            let summary = ShotSummaryAdapter.makeEngineSummary(
                from: record,
                ballSpeedMPH: speedSample?.mph
            )

            let tStr = String(format: "%.3f", timestampSec)
            let confStr = String(format: "%.1f", confidence)

            let pxPerSecStr: String
            if let px = speedSample?.pxPerSec {
                pxPerSecStr = String(format: "%.1f", px)
            } else {
                pxPerSecStr = "n/a"
            }

            let lockedStr = lockedNow ? "true" : "false"

            Log.info(
                .shot,
                "raw_motion " +
                "t=\(tStr) " +
                "conf=\(confStr) " +
                "px_s=\(pxPerSecStr) " +
                "locked=\(lockedStr)"
            )
            // --------------------------------------------------------------
            // Shot Authority Gate (the ONLY permission layer for shot start)
            // --------------------------------------------------------------

            let instantaneousPxPerSec = ballSpeedTracker.lastInstantaneousPxPerSec ?? 0

            // Presence (input only; no new sensors)
            let presenceOk = confidence >= authorityGate.config.presenceConfidenceThreshold

            // Motion candidate (input only)
            let movingNow = presenceOk && (instantaneousPxPerSec >= authorityGate.config.minMotionPxPerSec)

            // Motion phase derivation (outside the gate; gate consumes it)
            let motionPhase: MotionDensityPhase = {
                if !presenceOk { return .idle }

                if movingNow {
                    // First motion frame => approach; subsequent => impact
                    return wasMovingLastTick ? .impact : .approach
                } else {
                    // First frame after motion stops => separation; otherwise idle
                    return wasMovingLastTick ? .separation : .idle
                }
            }()

            wasMovingLastTick = movingNow

            // framesSinceIdle (context input; NOT derived inside the gate)
            if motionPhase == .idle {
                authorityIdleFrames = min(authorityIdleFrames + 1, 100000)
            } else {
                authorityIdleFrames = 0
            }

            let timeSinceLastAuth = lastAuthoritativeShotTimestampSec.map { timestampSec - $0 }

            // lifecycle context (input)
            let lifecycleCtx: ShotAuthorityLifecycleState = (shotLifecycle.state == .idle) ? .idle : .inProgress

            let decision = authorityGate.update(
                ShotAuthorityInput(
                    timestampSec: timestampSec,
                    ballLockConfidence: confidence,
                    clusterCompactness: nil,
                    instantaneousPxPerSec: instantaneousPxPerSec,
                    motionPhase: motionPhase,
                    framesSinceIdle: authorityIdleFrames,
                    timeSinceLastAuthoritativeShotSec: timeSinceLastAuth,
                    lifecycleState: lifecycleCtx
                )
            )

            let authorizedNow: Bool = {
                if case .authorized = decision { return true }
                return false
            }()

            if authorizedNow {
                lastAuthoritativeShotTimestampSec = timestampSec
            }

            // --------------------------------------------------------------
            // INTEGRATION RULE (MANDATORY)
            // Only allow idle → preImpact if authorizedNow == true.
            // --------------------------------------------------------------

            let shouldFeedLifecycle = (shotLifecycle.state != .idle) || authorizedNow
            guard shouldFeedLifecycle else { return }

            // When lifecycle is already in progress, we pass through true signals.
            // When idle, we only pass through on authorizedNow (guard above).
            let lifecycleInput = ShotLifecycleInput(
                timestampSec: timestampSec,
                ballLockConfidence: confidence,
                motionDensityPhase: motionPhase,
                ballSpeedPxPerSec: instantaneousPxPerSec,
                refusalReason: nil
            )

            if let record = shotLifecycle.update(lifecycleInput) {
                // Keep your existing completion handling here
                // (session store, summary adapter, etc.)
            } }
    }
}
