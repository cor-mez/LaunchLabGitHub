//
//  VisionDot.swift
//  LaunchLab
//

import CoreGraphics

struct VisionDot: Identifiable, Equatable {
    let id: Int
    let position: CGPoint
    let predicted: CGPoint?
    let velocity: CGVector?

    init(
        id: Int,
        position: CGPoint,
        predicted: CGPoint? = nil,
        velocity: CGVector? = nil
    ) {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.velocity = velocity
    }

    func updating(
        position: CGPoint? = nil,
        predicted: CGPoint? = nil,
        velocity: CGVector? = nil
    ) -> VisionDot {
        VisionDot(
            id: id,
            position: position ?? self.position,
            predicted: predicted ?? self.predicted,
            velocity: velocity ?? self.velocity
        )
    }
}
