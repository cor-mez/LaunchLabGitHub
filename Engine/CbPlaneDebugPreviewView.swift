//
//  CbPlaneDebugPreviewView.swift
//  LaunchLab
//
//  v2 — ZERO heavy work in updateUIView.
//  MTKViews simply display Metal textures produced by CbPlaneDebugCoordinator v2.
//

import SwiftUI
import Metal
import Accelerate
import CoreVideo

// -------------------------------------------------------------------------
// MARK: - SwiftUI Wrapper
// -------------------------------------------------------------------------

struct CbPlaneDebugPreviewView: UIViewRepresentable {

    @ObservedObject var coordinator: CbPlaneDebugCoordinatorV2

    func makeUIView(context: Context) -> CbDebugContainerView {
        let v = CbDebugContainerView()
        return v
    }

    func updateUIView(_ uiView: CbDebugContainerView, context: Context) {

        // MAIN TEXTURE PRIORITY ORDER:
        // normalized Cb > raw Cb > Y

        if coordinator.showNorm, let tex = coordinator.normTexture {
            uiView.displayMain(tex: tex)
        }
        else if coordinator.showCb, let tex = coordinator.cbTexture {
            uiView.displayMain(tex: tex)
        }
        else if coordinator.showY, let tex = coordinator.yTexture {
            uiView.displayMain(tex: tex)
        }
        else {
            uiView.displayMain(tex: nil)
        }

        // ZOOM TILES
        uiView.displayZoom(coordinator.zoomTextures)
    }
}

// -------------------------------------------------------------------------
// MARK: - UIKit Container Holding MTKViews
// -------------------------------------------------------------------------

final class CbDebugContainerView: UIView {

    // Main MTKView (letterboxed)
    let mainView = MetalCbView(sampleMode: .nearest)

    // 3 zoom tiles (linear sampling)
    let zoom1 = MetalCbView(sampleMode: .linear)
    let zoom2 = MetalCbView(sampleMode: .linear)
    let zoom3 = MetalCbView(sampleMode: .linear)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        setupMainView()
        setupZoomTiles()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMainLetterboxed()
        layoutZoomTiles()
    }

    // ---------------------------------------------------------------------
    // MARK: - Layout
    // ---------------------------------------------------------------------

    private func setupMainView() {
        addSubview(mainView)
        mainView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupZoomTiles() {
        [zoom1, zoom2, zoom3].forEach { z in
            z.translatesAutoresizingMaskIntoConstraints = false
            z.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            z.layer.cornerRadius = 10
            z.clipsToBounds = true
            addSubview(z)
        }
    }

    // Letterboxed because input is 1080×1920 (9:16 portrait)
    private func layoutMainLetterboxed() {
        let viewW = bounds.width
        let viewH = bounds.height

        let aspect: CGFloat = 1920.0 / 1080.0  // source is portrait 9:16
        let targetH = viewW * aspect

        var frame = CGRect.zero

        if targetH <= viewH {
            // vertical letterbox
            frame = CGRect(
                x: 0,
                y: (viewH - targetH) / 2,
                width: viewW,
                height: targetH
            )
        } else {
            // horizontal pillarbox
            let targetW = viewH / aspect * 1080.0 / 1080.0
            frame = CGRect(
                x: (viewW - targetW) / 2,
                y: 0,
                width: targetW,
                height: viewH
            )
        }

        mainView.frame = frame

        // Drawable must match physical pixels, not points
        let scale = UIScreen.main.scale
        mainView.drawableSize = CGSize(
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    private func layoutZoomTiles() {
        let pad: CGFloat = 10
        let tile: CGFloat = 120

        zoom1.frame = CGRect(
            x: bounds.width - tile - pad,
            y: pad,
            width: tile,
            height: tile
        )
        zoom2.frame = zoom1.frame.offsetBy(dx: 0, dy: tile + pad)
        zoom3.frame = zoom2.frame.offsetBy(dx: 0, dy: tile + pad)

        let scale = UIScreen.main.scale
        let ds = CGSize(width: tile * scale, height: tile * scale)

        zoom1.drawableSize = ds
        zoom2.drawableSize = ds
        zoom3.drawableSize = ds
    }

    // ---------------------------------------------------------------------
    // MARK: - Display Updating
    // ---------------------------------------------------------------------

    func displayMain(tex: MTLTexture?) {
        mainView.displayTexture(tex)
    }

    func displayZoom(_ textures: [MTLTexture]?) {
        guard let t = textures else {
            zoom1.displayTexture(nil)
            zoom2.displayTexture(nil)
            zoom3.displayTexture(nil)
            return
        }

        zoom1.displayTexture(t.count > 0 ? t[0] : nil)
        zoom2.displayTexture(t.count > 1 ? t[1] : nil)
        zoom3.displayTexture(t.count > 2 ? t[2] : nil)
    }
}
