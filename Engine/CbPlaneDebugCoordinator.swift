//
//  CbPlaneDebugCoordinator.swift
//  LaunchLab
//
//  FINAL WIRED VERSION:
//  - Subscribes to CbDebugRenderLoop output
//  - Publishes UI textures
//  - Handles freeze
//  - Handles ROI
//

import Foundation
import AVFoundation
import SwiftUI
import CoreVideo
import Combine

@MainActor
final class CbPlaneDebugCoordinatorV2: ObservableObject {

    // ------------------------------------------------------------------
    // MARK: - Published Textures → UI reads these
    // ------------------------------------------------------------------
    @Published var yTexture: MTLTexture?
    @Published var cbTexture: MTLTexture?
    @Published var normTexture: MTLTexture?
    @Published var zoomTextures: [MTLTexture]?

    // ------------------------------------------------------------------
    // MARK: - UI mode flags
    // ------------------------------------------------------------------
    @Published var showY: Bool = true
    @Published var showCb: Bool = false
    @Published var showNorm: Bool = false

    // ------------------------------------------------------------------
    // MARK: - HUD samples
    // ------------------------------------------------------------------
    @Published var sampleY: Int = 0
    @Published var sampleCb: Int = 0
    @Published var sampleNorm: Int = 0

    // ------------------------------------------------------------------
    // MARK: - Active buffer + ROI
    // ------------------------------------------------------------------
    @Published var latestBuffer: CVPixelBuffer?
    @Published var currentROI: CGRect?

    private var cancellables = Set<AnyCancellable>()

    // Render loop does all heavy texture generation
    private let renderLoop = CbDebugRenderLoop()

    weak var camera: CameraManager?

    // ------------------------------------------------------------------
    // MARK: - ATTACH CAMERA + DOT COORDINATOR
    // ------------------------------------------------------------------
    func attach(camera: CameraManager, dotCoordinator: DotTestCoordinator) {
        self.camera = camera

        camera.$latestWeakPixelBuffer
            .receive(on: RunLoop.main)
            .sink { [weak self] weakPB in
                guard let self else { return }

                let src = dotCoordinator.frozenBuffer ?? weakPB.buffer
                self.latestBuffer = src
                self.currentROI = dotCoordinator.currentROI

                if let s = src {
                    self.sampleCenterPixel(from: s)
                }

                self.recomputeCurrentTexture()
            }
            .store(in: &cancellables)

        dotCoordinator.$frozenBuffer
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeCurrentTexture()
            }
            .store(in: &cancellables)

        dotCoordinator.$currentROI
            .receive(on: RunLoop.main)
            .sink { [weak self] roi in
                self?.currentROI = roi
                self?.recomputeCurrentTexture()
            }
            .store(in: &cancellables)

        dotCoordinator.$liveBuffer
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeCurrentTexture()
            }
            .store(in: &cancellables)

        // LIVE UPDATES
        dotCoordinator.$liveBuffer
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeCurrentTexture()
            }
            .store(in: &cancellables)

        // ------------------------------------------------------------------
        // MARK: - SUBSCRIBE TO RENDER LOOP OUTPUT
        // ------------------------------------------------------------------
        renderLoop.$yTexture
            .receive(on: RunLoop.main)
            .assign(to: &$yTexture)

        renderLoop.$cbTexture
            .receive(on: RunLoop.main)
            .assign(to: &$cbTexture)

        renderLoop.$normTexture
            .receive(on: RunLoop.main)
            .assign(to: &$normTexture)

        renderLoop.$zoomTextures
            .receive(on: RunLoop.main)
            .assign(to: &$zoomTextures)
    }

    // ------------------------------------------------------------------
    // MARK: - MODE TOGGLE HANDLERS
    // ------------------------------------------------------------------
    func setShowY(_ v: Bool)  { showY = v; recomputeCurrentTexture() }
    func setShowCb(_ v: Bool) { showCb = v; recomputeCurrentTexture() }
    func setShowNorm(_ v: Bool) { showNorm = v; recomputeCurrentTexture() }

    // ------------------------------------------------------------------
    // MARK: - CENTRAL RECOMPUTE ENTRYPOINT
    // ------------------------------------------------------------------
    func recomputeCurrentTexture() {
        guard let buf = latestBuffer else { return }

        renderLoop.processFrame(
            pixelBuffer: buf,
            showY: showY,
            showCb: showCb,
            showNorm: showNorm,
            roi: currentROI
        )
    }

    // ------------------------------------------------------------------
    // MARK: - HUD SAMPLING
    // ------------------------------------------------------------------
    private func sampleCenterPixel(from buf: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }

        let w = CVPixelBufferGetWidth(buf)
        let h = CVPixelBufferGetHeight(buf)
        let cx = w / 2
        let cy = h / 2

        // Y-plane
        if let yBase = CVPixelBufferGetBaseAddressOfPlane(buf, 0) {
            let rb = CVPixelBufferGetBytesPerRowOfPlane(buf, 0)
            let ptr = yBase.assumingMemoryBound(to: UInt8.self)
            sampleY = Int(ptr[cy * rb + cx])
        }

        // Cb-plane
        if let uvBase = CVPixelBufferGetBaseAddressOfPlane(buf, 1) {
            let rb = CVPixelBufferGetBytesPerRowOfPlane(buf, 1)
            let ptr = uvBase.assumingMemoryBound(to: UInt8.self)
            let cbVal = Int(ptr[(cy / 2) * rb + (cx / 2) * 2])
            sampleCb = cbVal
            sampleNorm = cbVal
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Manual ROI update
    // ------------------------------------------------------------------
    func updateROI(from dotCoord: DotTestCoordinator?) {
        currentROI = dotCoord?.currentROI
        recomputeCurrentTexture()
    }
}
