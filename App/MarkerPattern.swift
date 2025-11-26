// File: Vision/Pattern/MarkerPattern.swift
//
//  MarkerPattern.swift
//  LaunchLab
//
//  Precomputed 72-dot, 3-ring marker pattern
//  North ring:  +37°, longitudes 7.5° + 15°·k
//  Equator:      0°, longitudes 0°   + 15°·k
//  South ring: −41°, longitudes 5°   + 15°·k
//  Radius: 0.021335 m
//

import Foundation
import simd

public enum MarkerPattern {

    // ---------------------------------------------------------------------
    // MARK: - Constants
    // ---------------------------------------------------------------------

    private static let r: Float = 0.021335

    private static let northLatitudeDeg: Float = +37.0
    private static let equatorLatitudeDeg: Float = 0.0
    private static let southLatitudeDeg: Float = -41.0

    // 24 samples per ring.
    private static let northLongitudesDeg: [Float] = stride(from: 7.5, to: 360.0, by: 15.0).map { Float($0) }
    private static let equatorLongitudesDeg: [Float] = stride(from: 0.0, to: 360.0, by: 15.0).map { Float($0) }
    private static let southLongitudesDeg: [Float] = stride(from: 5.0, to: 360.0, by: 15.0).map { Float($0) }

    // ---------------------------------------------------------------------
    // MARK: - Precomputed Model
    // ---------------------------------------------------------------------

    /// 72-point 3D model, precomputed at load.
    public static let model3D: [SIMD3<Float>] = {
        var pts: [SIMD3<Float>] = []
        pts.reserveCapacity(72)

        func appendRing(latitudeDeg: Float, longitudesDeg: [Float]) {
            let latRad = latitudeDeg * .pi / 180.0
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

        appendRing(latitudeDeg: northLatitudeDeg, longitudesDeg: northLongitudesDeg)
        appendRing(latitudeDeg: equatorLatitudeDeg, longitudesDeg: equatorLongitudesDeg)
        appendRing(latitudeDeg: southLatitudeDeg, longitudesDeg: southLongitudesDeg)

        return pts
    }()
}