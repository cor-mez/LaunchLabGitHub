// DotTestPreviewView.swift v4A

import SwiftUI
import MetalKit
import CoreVideo

struct DotTestPreviewView: UIViewRepresentable {

    @ObservedObject var coordinator: DotTestCoordinator
    let debugSurface: DotTestDebugSurface
    let showPreFAST9: Bool
    let showSRFAST9: Bool

    func makeUIView(context: Context) -> DotTestPreviewContainerView {
        DotTestPreviewContainerView()
    }

    func updateUIView(_ uiView: DotTestPreviewContainerView, context: Context) {
        let pb = coordinator.frozenBuffer ?? coordinator.liveBuffer

        if showPreFAST9, let pre = coordinator.preFast9Buffer {
            uiView.updatePlanar(pre)
            return
        }

        if showSRFAST9, let sr = coordinator.srFast9Buffer {
            uiView.updatePlanar(sr)
            return
        }

        switch debugSurface {
        case .none:
            uiView.updateCamera(pb)

        case .yNorm:
            uiView.updateDebug(.yNorm)

        case .yEdge:
            uiView.updateDebug(.yEdge)

        case .cbEdge:
            uiView.updateDebug(.cbEdge)

        case .fast9:
            uiView.updateDebug(.fast9)
        }
    }
}

final class DotTestPreviewContainerView: UIView {

    private let mtkView: MTKView

    override init(frame: CGRect) {
        mtkView = MTKView(frame: .zero, device: MetalCameraRenderer.shared.device)
        super.init(frame: frame)
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.contentScaleFactor = UIScreen.main.scale
        addSubview(mtkView)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        mtkView = MTKView(frame: .zero, device: MetalCameraRenderer.shared.device)
        super.init(coder: coder)
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.contentScaleFactor = UIScreen.main.scale
        addSubview(mtkView)
        backgroundColor = .black
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mtkView.frame = bounds
    }

    func updateCamera(_ pb: CVPixelBuffer?) {
        MetalDebugRouter.shared.renderCamera(pb, in: mtkView)
    }

    func updateDebug(_ surface: DotTestDebugSurface) {
        MetalDebugRouter.shared.renderSurface(surface, in: mtkView)
    }

    func updatePlanar(_ buf: vImage_Buffer) {
        let w = Int(buf.width)
        let h = Int(buf.height)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let tex = MetalCameraRenderer.shared.device.makeTexture(descriptor: desc) else { return }

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: buf.data,
            bytesPerRow: buf.rowBytes
        )

        MetalDebugRouter.shared.renderTexture(tex, in: mtkView)
    }
}
