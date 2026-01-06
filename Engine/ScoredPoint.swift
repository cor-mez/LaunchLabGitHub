//
//  EnginePoint.swift
//  LaunchLab
//
//  Canonical engine-level point representation.
//  Deliberately distinct from MetalDetector.ScoredPoint.
//

import CoreGraphics

struct EnginePoint {
    let point: CGPoint
    let score: Float
}
