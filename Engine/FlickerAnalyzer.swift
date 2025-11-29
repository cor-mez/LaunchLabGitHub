// File: Engine/FlickerAnalyzer.swift

import Foundation
import CoreVideo
import Metal
import simd

struct FlickerMetrics {
    let flickerModulation: Float
    let brightness: Float
    let brightnessDelta: Float
    let isDimPhase: Bool
    let isFlickerUnsafe: Bool
    let rowGradient: [Float]
}

final class FlickerAnalyzer {

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?

    private var prevBrightness: Float = 0.0

    init() {
        if let dev = MTLCreateSystemDefaultDevice() {
            device = dev
            commandQueue = dev.makeCommandQueue()

            var lib: MTLLibrary?
            if let defaultLib = try? dev.makeDefaultLibrary(bundle: .main) {
                lib = defaultLib
            } else {
                lib = dev.makeDefaultLibrary()
            }

            let function = lib?.makeFunction(name: "vpp_mean_rows")
            pipelineState = try? function.flatMap { try dev.makeComputePipelineState(function: $0) }

            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
            textureCache = cache
        } else {
            device = nil
            commandQueue = nil
            pipelineState = nil
            textureCache = nil
        }
    }

    func evaluate(pixelBuffer: CVPixelBuffer) -> FlickerMetrics {
        guard
            let device = device,
            let commandQueue = commandQueue,
            let pipelineState = pipelineState,
            let textureCache = textureCache
        else {
            return FlickerMetrics(
                flickerModulation: 0,
                brightness: 0,
                brightnessDelta: 0,
                isDimPhase: false,
                isFlickerUnsafe: false,
                rowGradient: []
            )
        }

        let planeIndex = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        guard width > 0, height > 0 else {
            return FlickerMetrics(
                flickerModulation: 0,
                brightness: 0,
                brightnessDelta: 0,
                isDimPhase: false,
                isFlickerUnsafe: false,
                rowGradient: []
            )
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            planeIndex,
            &cvTexture
        )

        guard
            status == kCVReturnSuccess,
            let cvTex = cvTexture,
            let srcTexture = CVMetalTextureGetTexture(cvTex)
        else {
            return FlickerMetrics(
                flickerModulation: 0,
                brightness: 0,
                brightnessDelta: 0,
                isDimPhase: false,
                isFlickerUnsafe: false,
                rowGradient: []
            )
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return FlickerMetrics(
                flickerModulation: 0,
                brightness: 0,
                brightnessDelta: 0,
                isDimPhase: false,
                isFlickerUnsafe: false,
                rowGradient: []
            )
        }

        let rowCount = height
        let rowBufferLength = rowCount * MemoryLayout<Float>.stride
        guard let rowBuffer = device.makeBuffer(length: rowBufferLength, options: .storageModeShared) else {
            return FlickerMetrics(
                flickerModulation: 0,
                brightness: 0,
                brightnessDelta: 0,
                isDimPhase: false,
                isFlickerUnsafe: false,
                rowGradient: []
            )
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(srcTexture, index: 0)
        encoder.setBuffer(rowBuffer, offset: 0, index: 0)

        let threadsPerGrid = MTLSize(width: 1, height: rowCount, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let ptr = rowBuffer.contents().bindMemory(to: Float.self, capacity: rowCount)
        var rowMeans = [Float](repeating: 0, count: rowCount)
        for i in 0..<rowCount {
            rowMeans[i] = ptr[i]
        }

        // brightness in [0,1]
        let brightness: Float
        if rowCount > 0 {
            var sum: Float = 0
            for v in rowMeans { sum += v }
            brightness = sum / Float(rowCount)
        } else {
            brightness = 0
        }

        let brightnessDelta = abs(brightness - prevBrightness)
        let refBrightness = max(prevBrightness, brightness)
        let normFactor = max(refBrightness, 0.05)

        var gradients = [Float](repeating: 0, count: rowCount)
        var maxAbsGrad: Float = 0

        if rowCount > 1 {
            for i in 0..<rowCount {
                let prevIndex = max(i - 1, 0)
                let nextIndex = min(i + 1, rowCount - 1)
                let g = (rowMeans[nextIndex] - rowMeans[prevIndex]) / (2.0 * normFactor)
                gradients[i] = g
                let ag = fabsf(g)
                if ag > maxAbsGrad {
                    maxAbsGrad = ag
                }
            }
        }

        let dimThreshold: Float
        if refBrightness > 0 {
            dimThreshold = refBrightness * 0.7 // 30% drop → dim phase
        } else {
            dimThreshold = 0.0
        }
        let isDimPhase = brightness < dimThreshold

        var isFlickerUnsafe = false
        if maxAbsGrad > 0.15 {
            isFlickerUnsafe = true
        } else if prevBrightness > 0, brightnessDelta > 0.10 * prevBrightness {
            isFlickerUnsafe = true
        }

        prevBrightness = brightness

        return FlickerMetrics(
            flickerModulation: maxAbsGrad,
            brightness: brightness,
            brightnessDelta: brightnessDelta,
            isDimPhase: isDimPhase,
            isFlickerUnsafe: isFlickerUnsafe,
            rowGradient: gradients
        )
    }
}
