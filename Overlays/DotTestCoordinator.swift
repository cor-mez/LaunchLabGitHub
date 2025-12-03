//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Receives frames from CameraManager,
//  manages freeze/unfreeze,
//  runs DotDetector in FULL-FRAME ROI,
//  feeds DotTestOverlayLayer with mapped points.
//

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

    /// Provided by DotTestMode to install a mapper when buffer dimensions change.
    var onDimensions: ((Int, Int) -> Void)?

    // MARK: - Wiring

    weak var camera: CameraManager?
    private var cancellable: AnyCancellable?

    func attach(camera: CameraManager) {
        self.camera = camera

        // Subscribe to camera frames.
        cancellable = camera.$latestPixelBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                guard let self = self else { return }
                guard let buffer = buffer else { return }

                // IMPORTANT: Notify dimensions ASAP.
                let w = CVPixelBufferGetWidth(buffer)
                let h = CVPixelBufferGetHeight(buffer)
                self.onDimensions?(w, h)

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

        overlayLayer.update(points: [],
                            bufferSize: .zero,
                            roiRect: nil)
        overlayLayer.updateClusterDebug(centroid: nil,
                                        radiusPx: 0)

        detectedCount = 0
        averageBrightness = 0
        roiSize = .zero
    }

    // MARK: - Detection

    func runDetection(with config: DotDetectorConfig) {
        guard let buffer = frozenBuffer ?? liveBuffer else { return }

        let width  = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        // DotTestMode ALWAYS uses FULL-FRAME ROI.
        let roi = CGRect(x: 0, y: 0,
                         width: CGFloat(width),
                         height: CGFloat(height))

        let detector = DotDetector(config: config)

        DispatchQueue.global(qos: .userInitiated).async {

            // 1) Run detector
            let points = detector.detect(in: buffer, roi: roi)

            // 2) Compute mean brightness in Y-plane
            var brightness: Double = 0
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                var sum: Double = 0
                for y in 0..<height {
                    let row = ptr.advanced(by: y * rowBytes)
                    for x in 0..<width {
                        sum += Double(row[x])
                    }
                }
                brightness = sum / Double(width * height * 255)
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

            // 3) Compute cluster info for debug overlay
            var centroid: CGPoint? = nil
            var radiusPx: CGFloat = 0

            if !points.isEmpty {
                var sx: CGFloat = 0
                var sy: CGFloat = 0
                for p in points {
                    sx += p.x
                    sy += p.y
                }
                let cx = sx / CGFloat(points.count)
                let cy = sy / CGFloat(points.count)
                centroid = CGPoint(x: cx, y: cy)

                var sumR: CGFloat = 0
                for p in points {
                    let dx = p.x - cx
                    let dy = p.y - cy
                    sumR += sqrt(dx*dx + dy*dy)
                }
                radiusPx = sumR / CGFloat(points.count)
            }

            let bufferSize = CGSize(width: width, height: height)
            let roiSize = CGSize(width: width, height: height)
            let count = points.count

            DispatchQueue.main.async {
                self.detectedCount = count
                self.averageBrightness = brightness
                self.roiSize = roiSize
                self.overlayLayer.update(points: points,
                                         bufferSize: bufferSize,
                                         roiRect: roi)
                self.overlayLayer.updateClusterDebug(centroid: centroid,
                                                     radiusPx: radiusPx)
            }
        }
    }
}