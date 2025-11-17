//
//  MarkerPattern.swift
//  LaunchLab
//
//  Precomputed 72-dot, 3-ring marker pattern
//  Latitudes: +38°, 0°, −38°
//  Longitudes: 0° … 345° in 15° steps
//  Radius: 0.021335 m
//

import Foundation
import simd

public enum MarkerPattern {

    // ---------------------------------------------------------------------
    // MARK: - Constants
    // ---------------------------------------------------------------------

    private static let r: Float = 0.021335

    private static let latitudesDeg: [Float] = [
        +38.0,
        0.0,
        -38.0
    ]

    private static let longitudesDeg: [Float] = stride(from: 0.0, to: 360.0, by: 15.0).map { Float($0) }

    // ---------------------------------------------------------------------
    // MARK: - Precomputed Model
    // ---------------------------------------------------------------------

    /// 72-point 3D model, precomputed at load.
    public static let model3D: [SIMD3<Float>] = {
        var pts: [SIMD3<Float>] = []
        pts.reserveCapacity(72)

        for latDeg in latitudesDeg {
            let latRad = latDeg * .pi / 180.0
            let cosLat = cos(latRad)
            let sinLat = sin(latRad)

            for lonDeg in longitudesDeg {
                let lonRad = lonDeg * .pi / 180.0
                let x = r * cosLat * cos(lonRad)
                let y = r * cosLat * sin(lonRad)
                let z = r * sinLat
                pts.append(SIMD3<Float>(x, y, z))
            }
        }

        return pts
    }()
}
