//
//  RSResult.swift
//  LaunchLab
//
//  Expanded RS observability contract.
//  No physics claims — observables only.
//

import Foundation
import CoreGraphics

struct RSResult {

    // Scalar energy
    let zmax: Float
    let dz: Float

    // Quality / structure metrics
    let r2: Float
    let nonu: Float
    let lw: Float
    let edge: Float

    // Row-adjacent observability
    let rowAdjCorrelation: Float      // [-1, 1]
    let bandingScore: Float           // global periodicity indicator

    // Classification
    let isImpulse: Bool

    // Epistemic explanation
    let rejectionReason: String
}
