//
//  TrajectoryHistoryOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import simd
import UIKit

final class TrajectoryHistoryOverlayLayer: CALayer {

    // Store up to N frames of dot paths
    private let maxHistory = 60

    // History map: dotID → [CGPoint]
    private var trajectories: [Int: [CGPoint]] = [:]

    private var latestFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------
    public func update(frame: VisionFrameData?) {
        latestFrame = frame
        guard let frame else { return }

        let w = frame.width
        let h = frame.height
        let viewSize = bounds.size

        // Append mapped points to history
        for dot in frame.dots {
            let viewPt = VisionOverlaySupport.mapPointFromBufferToView(
                point: dot.position,
                bufferWidth: w,
                bufferHeight: h,
                viewSize: viewSize
            )

            var arr = trajectories[dot.id] ?? []
            arr.append(viewPt)
            if arr.count > maxHistory { arr.removeFirst() }
            trajectories[dot.id] = arr
        }

        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard latestFrame != nil else { return }

        ctx.setLineWidth(1.5)

        for (_, points) in trajectories {
            guard points.count > 1 else { continue }

            // Color fades from white → cyan over time
            for i in 1..<points.count {
                let alpha = CGFloat(Double(i) / Double(points.count))
                let color = CGColor(
                    red: 0,
                    green: alpha,
                    blue: 1,
                    alpha: alpha
                )

                ctx.setStrokeColor(color)
                ctx.beginPath()
                ctx.move(to: points[i - 1])
                ctx.addLine(to: points[i])
                ctx.strokePath()
            }
        }
    }
}