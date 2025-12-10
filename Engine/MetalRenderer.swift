import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

final class MetalRenderer {

    static let shared = MetalRenderer()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let textureCache: CVMetalTextureCache

    var quad: MTLBuffer!
    var samplerNearest: MTLSamplerState!
    var samplerLinear: MTLSamplerState!

    var p_y_extract: MTLComputePipelineState!
    var p_y_min: MTLComputePipelineState!
    var p_y_max: MTLComputePipelineState!
    var p_y_norm: MTLComputePipelineState!
    var p_y_edge: MTLComputePipelineState!
    var p_y_crop: MTLComputePipelineState!
    var p_y_sr: MTLComputePipelineState!

    var p_cb_extract: MTLComputePipelineState!
    var p_cb_min: MTLComputePipelineState!
    var p_cb_max: MTLComputePipelineState!
    var p_cb_norm: MTLComputePipelineState!
    var p_cb_edge: MTLComputePipelineState!
    var p_cb_crop: MTLComputePipelineState!
    var p_cb_sr: MTLComputePipelineState!

    var p_fast9: MTLComputePipelineState!
    var p_fast9_score: MTLComputePipelineState!

    var p_preview: MTLRenderPipelineState!
    var p_blit: MTLRenderPipelineState!

    var yCompute: YCompute!
    var cbCompute: CbCompute!
    var fast9Compute: Fast9Compute!

    var frameW: Int = 0
    var frameH: Int = 0
    var cbFrameW: Int = 0
    var cbFrameH: Int = 0
    var roiYW: Int = 0
    var roiYH: Int = 0
    var roiCbW: Int = 0
    var roiCbH: Int = 0
    var srYW: Int = 0
    var srYH: Int = 0
    var srCbW: Int = 0
    var srCbH: Int = 0

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!

        var tc: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &tc)
        textureCache = tc!

        let quadData: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        quad = device.makeBuffer(bytes: quadData, length: quadData.count * MemoryLayout<Float>.size)

        let sd0 = MTLSamplerDescriptor()
        sd0.minFilter = .nearest
        sd0.magFilter = .nearest
        sd0.sAddressMode = .clampToEdge
        sd0.tAddressMode = .clampToEdge
        samplerNearest = device.makeSamplerState(descriptor: sd0)

        let sd1 = MTLSamplerDescriptor()
        sd1.minFilter = .linear
        sd1.magFilter = .linear
        sd1.sAddressMode = .clampToEdge
        sd1.tAddressMode = .clampToEdge
        samplerLinear = device.makeSamplerState(descriptor: sd1)

        buildYPipelines()
        buildCbPipelines()
        buildFast9Pipelines()
        buildRenderPipelines()
        buildBlitPipelines()
        buildModules()
    }

    private func buildYPipelines() {}
    private func buildCbPipelines() {}
    private func buildFast9Pipelines() {}
    private func buildRenderPipelines() {}
    private func buildBlitPipelines() {}
    private func buildModules() {}
}
private extension MetalRenderer {

    func buildYPipelines() {
        p_y_extract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_extract")!)
        p_y_min = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_min")!)
        p_y_max = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_max")!)
        p_y_norm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_norm")!)
        p_y_edge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_edge")!)
        p_y_crop = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_y")!)
        p_y_sr = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_y")!)
    }

    func buildCbPipelines() {
        p_cb_extract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_extract")!)
        p_cb_min = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_min")!)
        p_cb_max = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_max")!)
        p_cb_norm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_norm")!)
        p_cb_edge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_edge")!)
        p_cb_crop = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_cb")!)
        p_cb_sr = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_cb")!)
    }

    func buildFast9Pipelines() {
        p_fast9 = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_gpu")!)
        p_fast9_score = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_score_gpu")!)
    }

    func buildRenderPipelines() {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "passthroughVertex")
        desc.fragmentFunction = library.makeFunction(name: "passthroughFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        p_preview = try! device.makeRenderPipelineState(descriptor: desc)
    }

    func buildBlitPipelines() {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "copyVertex")
        desc.fragmentFunction = library.makeFunction(name: "copyFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        p_blit = try! device.makeRenderPipelineState(descriptor: desc)
    }

    func buildModules() {
        yCompute = YCompute(device: device, queue: queue)
        cbCompute = CbCompute(device: device, queue: queue)
        fast9Compute = Fast9Compute(device: device, queue: queue)
    }
}