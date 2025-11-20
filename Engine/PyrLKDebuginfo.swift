//
//  PyrLKDebugInfo.swift
//  LaunchLab
//

import Foundation
import simd

public struct PyrLKLevelDebug {
    public let level: Int
    public let initial: SIMD2<Float>
    public let refined: SIMD2<Float>
    public let flow: SIMD2<Float>
    public let error: Float
}

public struct PyrLKDotDebug {
    public let id: Int
    public let levels: [PyrLKLevelDebug]
}

public final class PyrLKDebugInfo {
    public var dots: [PyrLKDotDebug] = []

    public init() {}

    public func clear() {
        dots.removeAll()
    }

    public func add(levelInfo: PyrLKDotDebug) {
        dots.append(levelInfo)
    }
}