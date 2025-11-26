// File: Vision/RS/RSWindowBuilder.swift
//
//  RSWindowBuilder.swift
//  LaunchLab
//
//  Maintains a rolling 3-frame RS-PnP window for each shot.
//  Does not perform the actual PnP solve; it only selects frames.
//

import Foundation
import CoreGraphics

struct RSWindow {
    let frames: [VisionFrameData]
    /// Locked-run index of the first frame in the window.
    let startLockedRunLength: Int
}

final class RSWindowBuilder {

    private var buffer: [VisionFrameData] = []
    private var lastLockedRunLength: Int = 0
    private var shotHasWindow: Bool = false

    func reset() {
        buffer.removeAll()
        lastLockedRunLength = 0
        shotHasWindow = false
    }

    /// Pushes a frame through the RS window selection logic.
    ///
    /// - Parameters:
    ///   - frame: Ball-only frame after BallLock + Velocity.
    ///   - isLocked: Current BallLock state.
    ///   - clusterQuality: Cluster Q (0–1).
    ///   - rsResult: Rolling-shutter degeneracy result for this frame.
    ///   - lockedRunLength: Number of consecutive locked frames so far.
    ///
    /// - Returns: A 3-frame RS window once per shot, otherwise `nil`.
    func push(
        frame: VisionFrameData,
        isLocked: Bool,
        clusterQuality: CGFloat,
        rsResult: RSDegeneracyResult,
        lockedRunLength: Int
    ) -> RSWindow? {

        // Shot ended → reset when we drop out of lock and previously had one.
        if !isLocked && lastLockedRunLength > 0 {
            buffer.removeAll()
            shotHasWindow = false
        }
        lastLockedRunLength = lockedRunLength

        guard !shotHasWindow else {
            // Already built a window for this shot.
            return nil
        }

        // GOOD frame definition.
        let isGoodFrame =
            isLocked &&
            clusterQuality >= 0.55 &&
            rsResult.rsConfidence >= 0.60 &&
            !rsResult.criticalDegeneracy

        // Prefer frames 2–4 in the locked run (approximate "post-launch").
        guard isGoodFrame,
              (2...4).contains(lockedRunLength) else {
            return nil
        }

        buffer.append(frame)

        // Keep last 3 good frames in the preferred range.
        if buffer.count > 3 {
            buffer.removeFirst(buffer.count - 3)
        }

        guard buffer.count == 3 else {
            return nil
        }

        shotHasWindow = true
        return RSWindow(
            frames: buffer,
            startLockedRunLength: lockedRunLength - 2
        )
    }
}