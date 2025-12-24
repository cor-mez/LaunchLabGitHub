//MetalRenderer.swift

import Foundation
import Metal
import MetalKit
import CoreVideo

struct PreviewUniforms {
    var debugMode: UInt32
    var _pad0: UInt32 = 0
    var threshold: Float
    var _pad1: Float = 0
}

struct CornerOut {
    var x: UInt16
    var y: UInt16
    var score: UInt16
}

struct Counter {
    var count: UInt32
}
@MainActor
final class MetalRenderer {
    
    static let shared = MetalRenderer()
    var disablePresentation: Bool = true
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let previewPSO: MTLRenderPipelineState
    let textureCache: CVMetalTextureCache
    let sampler: MTLSamplerState
    let debugTexture: MTLTexture
    let maxCorners = 4096
    
    let cornerBuffer: MTLBuffer
    let counterBuffer: MTLBuffer
    
    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("MTLCreateSystemDefaultDevice() failed")
        }
        device = dev
        
        guard let q = dev.makeCommandQueue() else {
            fatalError("makeCommandQueue() failed")
        }
        queue = q
        
        guard let lib = dev.makeDefaultLibrary() else {
            fatalError("makeDefaultLibrary() failed")
        }
        library = lib
        
        let v = library.makeFunction(name: "passthroughVertex")!
        let f = library.makeFunction(name: "passthroughFragment")!
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            previewPSO = try dev.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create preview pipeline: \(error)")
        }
        
        // Sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        
        guard let samp = dev.makeSamplerState(descriptor: samplerDesc) else {
            fatalError("Failed to create sampler")
        }
        sampler = samp
        
        // Texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        guard let c = cache else {
            fatalError("CVMetalTextureCacheCreate failed")
        }
        textureCache = c
        
        // Debug 1×1 white texture
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        
        guard let dbgTex = dev.makeTexture(descriptor: texDesc) else {
            fatalError("Failed to create debug texture")
        }
        
        var white: UInt8 = 255
        dbgTex.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 1
        )
        
        debugTexture = dbgTex
        
        cornerBuffer = device.makeBuffer(
            length: MemoryLayout<CornerOut>.stride * maxCorners,
            options: .storageModeShared
        )!
        
        counterBuffer = device.makeBuffer(
            length: MemoryLayout<Counter>.stride,
            options: .storageModeShared
        )!
        
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Render
    // -------------------------------------------------------------------------
    
    func renderPreview(
        texture tex: MTLTexture?,
        in view: MTKView,
        isR8: Bool,
        forceSolid: Bool
    ) {
        guard
            let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let cb = queue.makeCommandBuffer(),
            let enc = cb.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        
        enc.setRenderPipelineState(previewPSO)
        
        enc.setFragmentTexture(tex ?? debugTexture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        
        enc.setViewport(
            MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(view.drawableSize.width),
                height: Double(view.drawableSize.height),
                znear: 0,
                zfar: 1
            )
        )
      
        enc.setCullMode(.none)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Y Plane → Metal Texture
    // -------------------------------------------------------------------------
    
    func makeYPlaneTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        
        let planeIndex = 0
        
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var cvTex: CVMetalTexture?
        
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            planeIndex,
            &cvTex
        )
        
        if DebugProbe.isEnabled(.capture) {
           
        }
        
        guard
            status == kCVReturnSuccess,
            let metalTex = cvTex.flatMap({ CVMetalTextureGetTexture($0) })
        else {
            return nil
        }
        
        return metalTex
    }
    
    func resetCornerCounter() {
        let ptr = counterBuffer.contents()
            .bindMemory(to: Counter.self, capacity: 1)
        ptr.pointee.count = 0
    }
    func readCorners() -> [CornerOut] {
        let counterPtr = counterBuffer.contents()
            .bindMemory(to: Counter.self, capacity: 1)
        
        let count = Int(counterPtr.pointee.count)
        guard count > 0 else { return [] }
        
        let cornerPtr = cornerBuffer.contents()
            .bindMemory(to: CornerOut.self, capacity: count)
        
        return Array(UnsafeBufferPointer(start: cornerPtr, count: count))
    }
}
