//
//  RSTimingCalibratedModel.swift
//  LaunchLab
//

import Foundation
import simd

public final class RSTimingCalibratedModel {

    public let readout: Float
    public let curve: [Float]

    public init(readout: Float, curve: [Float]) {
        self.readout = readout
        self.curve = curve
    }

    public func timeForRow(_ row: Float, maxRow: Float) -> Float {
        if curve.count < 2 || maxRow < 1 { return row / maxRow * readout }

        let t = row / maxRow
        let idx = Int(Float(curve.count - 1) * t)
        if idx < 0 { return 0 }
        if idx >= curve.count { return readout }

        return curve[idx] * readout
    }
}