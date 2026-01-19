//
//  RSResult.swift
//  LaunchLab
//

struct RSResult {

    let zmax: Float
    let dz: Float
    let r2: Float
    let nonu: Float
    let lw: Float
    let edge: Float

    /// True ONLY when onset criteria are satisfied
    let isImpulse: Bool

    /// Populated ONLY when isImpulse == false
    let rejectionReason: String
}
