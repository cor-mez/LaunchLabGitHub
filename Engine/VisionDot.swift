// VisionDot.swift
import CoreGraphics
import simd

public struct VisionDot {
    public let id: Int
    public var position: CGPoint
    public var predicted: CGPoint?
    public var confidence: Float
    public var fbError: Float
    public var flow: SIMD2<Float>?   // NEW FIELD

    public init(
        id: Int,
        position: CGPoint,
        predicted: CGPoint? = nil,
        confidence: Float = 1.0,
        fbError: Float = 0.0,
        flow: SIMD2<Float>? = nil
    ) {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.confidence = confidence
        self.fbError = fbError
        self.flow = flow
    }
}
