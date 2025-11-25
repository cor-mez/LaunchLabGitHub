//
//  DotPattern.swift
//  LaunchLab
//

import Foundation
import simd

public enum DotPattern {

    /// Placeholder 72-dot pattern.
    /// Real pattern will be inserted later.
    public static let pattern3D: [SIMD3<Float>] = {
        var arr: [SIMD3<Float>] = []
        arr.reserveCapacity(72)
        for _ in 0..<72 {
            arr.append(SIMD3<Float>(0, 0, 0))
        }
        return arr
    }()
}
