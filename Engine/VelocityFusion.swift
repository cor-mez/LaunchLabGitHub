//
//  VelocityFusion.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

struct VelocityState {
    let id: Int
    let velocity: CGVector
    let predicted: CGPoint
    let corrected: CGPoint
    let isStable: Bool
}

final class VelocityFusion {

    func fuse(
        kfDots: [VisionDot],
        lkDots: [VisionDot],
        trackedDots: [VisionDot]
    ) -> [VelocityState] {

        var results: [VelocityState] = []
        results.reserveCapacity(kfDots.count)

        for d in trackedDots {
            let kf = kfDots.first { $0.id == d.id }
            let lk = lkDots.first { $0.id == d.id }

            let vel = kf?.velocity ?? .zero
            let pred = kf?.predicted ?? d.position
            let corr = lk?.position ?? d.position

            let stable = abs(vel.dx) < 100 && abs(vel.dy) < 100

            results.append(
                VelocityState(
                    id: d.id,
                    velocity: vel,
                    predicted: pred,
                    corrected: corr,
                    isStable: stable
                )
            )
        }

        return results
    }
}