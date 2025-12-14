//
//  MetalContext.swift
//  LaunchLab
//
//  Global Metal device + command queue + library loader.
//

import Foundation
import Metal

public final class MetalContext {

    public static let shared = MetalContext()

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public let library: MTLLibrary

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal unavailable on this device.")
        }
        device = dev

        guard let q = dev.makeCommandQueue() else {
            fatalError("Metal command queue creation failed.")
        }
        queue = q

        // Library: loads all *.metal files in target
        guard let lib = try? dev.makeDefaultLibrary(bundle: .main) else {
            fatalError("Failed to load Metal default library.")
        }
        library = lib
    }
}
