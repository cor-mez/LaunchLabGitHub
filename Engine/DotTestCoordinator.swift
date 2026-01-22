//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Rolling-Shutter Measurement Harness (V7)
//
//  ROLE (STRICT):
//  - OBSERVATION ONLY
//  - NO authority logic
//  - NO heuristics
//  - Produces explicit facts only
//

import CoreMedia
import CoreVideo
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    // -----------------------------------------------------------------
    // Observers
    // -----------------------------------------------------------------

    private let cadenceEstimator = CadenceEstimator()
    private let shotAuthority    = ShotLifecycleController()

    private init() {}

    // -----------------------------------------------------------------
    // Frame Processing
    // -----------------------------------------------------------------

    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {

        let tSec = CMTimeGetSeconds(timestamp)

        cadenceEstimator.push(timestamp: tSec)
        let captureValid = cadenceEstimator.estimatedFPS >= 90

        let input = ShotLifecycleInput(
            timestampSec: tSec,
            captureValid: captureValid,
            rsObservable: false,          // Phase2 probe does not gate shots
            eligibleForShot: false,
            impactObserved: false,
            postImpactObserved: false,
            confirmedByUpstream: false,
            refusalReason: captureValid ? nil : .insufficientConfidence
        )

        Task {
            _ = await shotAuthority.update(input)
        }
    }
}
