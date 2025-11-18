//
//  DotModel.swift
//  LaunchLab
//
//  Static 72-dot 3D fiducial pattern (3-ring, 24-dot per ring)
//  Structure-of-Arrays (SoA) layout for RS-PnP
//

import Foundation
import simd

public struct DotModel {

    // ---------------------------------------------------------
    // MARK: - Public Read-Only SoA Arrays
    // ---------------------------------------------------------
    public let modelX: [Float]
    public let modelY: [Float]
    public let modelZ: [Float]

    // Total dots
    public static let count = 72

    // ---------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------
    public init() {
        // Sphere radius (golf ball) in millimeters
        let R: Float = 21.335

        // Latitudes in degrees for the 3 rings
        let latDeg: [Float] = [ 38.0, 0.0, -38.0 ]
        let latRad = latDeg.map { $0 * .pi / 180.0 }

        // 24 longitudes per ring
        let nLong = 24
        let dLon = 2.0 * Float.pi / Float(nLong)

        var xs = [Float]()
        var ys = [Float]()
        var zs = [Float]()

        xs.reserveCapacity(DotModel.count)
        ys.reserveCapacity(DotModel.count)
        zs.reserveCapacity(DotModel.count)

        // -----------------------------------------------------
        // ID Assignment:
        // Ring 0 (lat +38°): ids 0–23
        // Ring 1 (lat   0°): ids 24–47
        // Ring 2 (lat –38°): ids 48–71
        // Within ring: increasing longitude at steps of 15°
        // -----------------------------------------------------

        for (ringIndex, φ) in latRad.enumerated() {
            let baseID = ringIndex * nLong

            // cos(lat) and sin(lat)
            let sinφ = sin(φ)
            let cosφ = cos(φ)

            for k in 0..<nLong {
                let id = baseID + k
                let λ = Float(k) * dLon     // longitude

                // Standard spherical → Cartesian
                // x = R * cosφ * cosλ
                // y = R * sinφ
                // z = R * cosφ * sinλ
                let cosλ = cos(λ)
                let sinλ = sin(λ)

                let x = R * cosφ * cosλ
                let y = R * sinφ
                let z = R * cosφ * sinλ

                xs.append(x)
                ys.append(y)
                zs.append(z)

                // Sanity: enforce exact ID path length
                assert(xs.count == id + 1)
            }
        }

        self.modelX = xs
        self.modelY = ys
        self.modelZ = zs
    }

    // ---------------------------------------------------------
    // MARK: - Access Single 3D Point
    // ---------------------------------------------------------
    @inline(__always)
    public func point(for id: Int) -> SIMD3<Float> {
        // id ∈ 0…71
        let i = id & 0x7F   // clamp via mask (fast, valid for 0–127)
        return SIMD3<Float>(modelX[i], modelY[i], modelZ[i])
    }
}