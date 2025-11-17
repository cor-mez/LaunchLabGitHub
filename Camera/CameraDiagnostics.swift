//
//  CameraDiagnostics.swift
//  LaunchLab
//

import Foundation

struct CameraDiagnostics: Identifiable {
    let id = UUID()

    // MARK: - Timing
    let timestamp: Double
    let fps: Double
    let dt: Double
    let dropped: Bool

    // MARK: - Camera state
    let exposure: Double
    let iso: Float
    let brightness: Float   // simple estimation from Y-plane sample
    let rollingShutterLineTime: Double?

    // MARK: - Metal
    let metalTextureAvailable: Bool

    // MARK: - Dot Detection
    let dotCount: Int
    let dotThreshold: UInt8
}
