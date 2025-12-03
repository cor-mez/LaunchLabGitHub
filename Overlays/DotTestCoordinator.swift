// File: Overlays/DotTestCoordinator.swift
// DotTestCoordinator — subscribes to CameraManager.latestPixelBuffer,
// manages freeze/unfreeze, runs DotDetector, and feeds DotTestOverlayLayer.

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import Combine

@MainActor
final class DotTestCoordinator: ObservableObject {

    // MARK: - Buffers

    @Published var liveBuffer: CVPixelBuffer?
    @Published var frozenBuffer: CVPixelBuffer?

    var isFrozen: Bool = false

    // MARK: - Telemetry

    @Published private(set) var detectedCount: Int = 0
    @Published private(set) var averageBrightness: Double = 0
    @Published private(set) var roiSize: CGSize = .zero

    // MARK: - Overlay

    let overlayLayer = DotTestOverlayLayer()

    var onDimensions: ((Int, Int) -> Void)?     // ← ADD HERE

    // MARK: - Wiring

    weak var camera: CameraManager?
    private var cancellable: AnyCancellable?

    func attach(camera: CameraManager) {
        self.camera = camera

        // Subscribe to live pixel buffers from the camera.
        cancellable = camera.$latestPixelBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                guard let self = self, let buffer = buffer else { return }
                if !self.isFrozen {
                    self.liveBuffer = buffer
                }
            }
    }

    // MARK: - Freeze / Unfreeze

    func freezeFrame() {
        guard let live = liveBuffer else { return }
        frozenBuffer = live
        isFrozen = true
    }

    func unfreeze() {
        frozenBuffer = nil
        isFrozen = false
        overlayLayer.update(points: [], bufferSize: .zero, roiRect: nil)
        overlayLayer.updateClusterDebug(centroid: nil, radiusPx: 0)
        detectedCount = 0
        averageBrightness = 0
        roiSize = .zero
    }

    // MARK: - Detection

    func runDetection(with config: DotDetectorConfig) {
        guard let buffer = frozenBuffer ?? liveBuffer else { return }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        // ---------------------------------------------------------------
        // ⭐ NEW CORRECT BEHAVIOR:
        // DotTestMode ALWAYS uses full-frame ROI for raw signal tuning.
        // ---------------------------------------------------------------
        let roi = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )

        // Detector
        let detector = DotDetector(config: config)

        DispatchQueue.global(qos: .userInitiated).async {

            // 1) Run detector inside the FULL frame
            let points = detector.detect(in: buffer, roi: roi)

            // 2) Compute brightness over ROI (Y-plane 0–1)
            var brightness: Double = 0
            var roiW = 0
            var roiH = 0

            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                let ptr = base.assumingMemoryBound(to: UInt8.self)

                let x0 = 0
                let y0 = 0
                let x1 = width
                let y1 = height

                roiW = width
                roiH = height

                var sum: Double = 0
                for y in y0..<y1 {
                    let row = ptr.advanced(by: y * rowBytes)
                    for x in x0..<x1 {
                        sum += Double(row[x])
                    }
                }

                brightness = sum / Double(roiW * roiH * 255)
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

            // 3) Simple cluster centroid (for debug)
            var centroid: CGPoint? = nil
            var radiusPx: CGFloat = 0

            if !points.isEmpty {
                var sumX: CGFloat = 0
                var sumY: CGFloat = 0
                for p in points {
                    sumX += p.x
                    sumY += p.y
                }
                let cx = sumX / CGFloat(points.count)
                let cy = sumY / CGFloat(points.count)
                centroid = CGPoint(x: cx, y: cy)

                var sumR: CGFloat = 0
                for p in points {
                    let dx = p.x - cx
                    let dy = p.y - cy
                    sumR += sqrt(dx * dx + dy * dy)
                }
                radiusPx = sumR / CGFloat(points.count)
            }

            let bufferSize = CGSize(width: width, height: height)
            let roiSize = CGSize(width: roiW, height: roiH)
            let count = points.count

            DispatchQueue.main.async {
                self.detectedCount = count
                self.averageBrightness = brightness
                self.roiSize = roiSize
                self.overlayLayer.update(
                    points: points,
                    bufferSize: bufferSize,
                    roiRect: roi
                )
                self.overlayLayer.updateClusterDebug(
                    centroid: centroid,
                    radiusPx: radiusPx
                )
            }
        }
    }
}
