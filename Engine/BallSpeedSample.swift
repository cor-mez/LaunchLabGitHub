//
//  BallSpeedSample.swift
//  LaunchLab
//
//  Immutable engine output for ball speed calculation
//

import Foundation

struct BallSpeedSample {
    let pxPerSec: Double
    let mph: Double
    let sampleCount: Int
    let spanSec: Double
    let confidence: BallSpeedConfidence
}
