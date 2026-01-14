//
//  ShotLock.swift
//  LaunchLab
//
//  V1: Single-shot authority latch
//

struct ShotLock {

    private(set) var isLocked: Bool = false
    private(set) var shotTimestamp: Double?
    private(set) var shotZMax: Float?

    mutating func tryLock(
        timestamp: Double,
        zmax: Float
    ) -> Bool {

        guard !isLocked else { return false }

        isLocked = true
        shotTimestamp = timestamp
        shotZMax = zmax
        return true
    }

    mutating func reset() {
        isLocked = false
        shotTimestamp = nil
        shotZMax = nil
    }
}
