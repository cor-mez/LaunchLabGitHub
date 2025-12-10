//
//  MetalCbView.swift
//  LaunchLab
//
//  GPU-fast MTKView renderer for Planar8 / r8Unorm textures.
//  Uses pull-model: displayTexture() triggers a draw.
//  No CPU-GPU copies. No UIImage.
//

import MetalKit

final class MetalCbView: MTKView {

    enum Sampling {
        case nearest
        case linear
    }

    private var pipeline: MTLRenderPipelineState!
    private var sampler: MTLSamplerState!
    private var quadBuffer: MTLBuffer!
    private var currentTexture: MTLTexture?

    private let deviceRef = MetalContext.shared.device
    private let queueRef  = MetalContext.shared.queue

    // MARK: - Init
    init(sampleMode: Sampling = .nearest) {
        super.init(frame: .zero, device: MetalContext.shared.device)

        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        colorPixelFormat = .bgra8Unorm

        buildQuad()
        buildSampler(mode: sampleMode)
        buildPipeline()
    }

    required init(coder: NSCoder) {
        fatalError("MetalCbView does not support IB")
    }

    // MARK: - Public
    func displayTexture(_ tex: MTLTexture?) {
        currentTexture = tex
        setNeedsDisplay()
    }

    func setSampling(_ mode: Sampling) {
        buildSampler(mode: mode)
    }

    // MARK: - Build Pipeline
    private func buildPipeline() {
        let library = MetalContext.shared.library

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "cbview_vertex")
        desc.fragmentFunction = library.makeFunction(name: "cbview_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipeline = try deviceRef.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Pipeline error: \(error)")
        }
    }

    private func buildSampler(mode: Sampling) {
        let sd = MTLSamplerDescriptor()
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge

        switch mode {
        case .nearest:
            sd.minFilter = .nearest
            sd.magFilter = .nearest
        case .linear:
            sd.minFilter = .linear
            sd.magFilter = .linear
        }

        sampler = deviceRef.makeSamplerState(descriptor: sd)
    }

    private func buildQuad() {
        let quad: [Float] = [
            -1.0, -1.0,   0.0, 1.0,
             1.0, -1.0,   1.0, 1.0,
            -1.0,  1.0,   0.0, 0.0,
             1.0,  1.0,   1.0, 0.0
        ]
        quadBuffer = deviceRef.makeBuffer(bytes: quad,
                                          length: MemoryLayout<Float>.size * quad.count)
    }

    // MARK: - Draw
    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable else { return }
        guard let tex = currentTexture else {
            clearDrawable(drawable)
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.colorAttachments[0].storeAction = .store

        guard let cmd = queueRef.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    private func clearDrawable(_ drawable: CAMetalDrawable) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.colorAttachments[0].storeAction = .store

        guard let cmd = queueRef.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
