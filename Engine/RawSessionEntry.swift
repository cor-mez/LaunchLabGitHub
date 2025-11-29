// File: Engine/Logging/RawSessionEntry.swift
//
//  RawSessionEntry.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

struct RawSessionIntrinsics: Codable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
}

struct RawSessionDot: Codable {
    let x: Float
    let y: Float
}

struct RawSessionResidual: Codable {
    let id: Int
    let ex: Float
    let ey: Float
    let weight: Float
}

struct RawSessionEntry: Codable {
    let frameIndex: Int
    let timestamp: Double

    let intrinsics: RawSessionIntrinsics

    let imuGravity: [Float]
    let imuRotationRate: [Float]
    let imuAttitude: [Float]   // [x, y, z, w]

    let iso: Float
    let exposureDuration: Double

    let ballRadiusPx: Float?
    let ballLockState: Int?
    let ballLockQuality: Float?

    let rsShear: Float?
    let rsRowSpan: Float?
    let rsConfidence: Float?
    let flickerModulation: Float?

    let unsafeLighting: Bool
    let unsafeFrameRate: Bool
    let unsafeThermal: Bool

    let dots: [RawSessionDot]
    let residuals: [RawSessionResidual]
}
