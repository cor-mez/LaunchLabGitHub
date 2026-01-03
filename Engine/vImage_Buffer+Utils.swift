//
//  vImage_Buffer+Utils.swift
//  LaunchLab
//

import Accelerate
import Darwin   // ⬅️ Explicitly import C allocator symbols

extension vImage_Buffer {

    static func makePlanar8(width: Int, height: Int) -> vImage_Buffer {
        let rowBytes = width
        guard let data = Darwin.malloc(height * rowBytes) else {
            fatalError("malloc failed for vImage buffer")
        }

        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: rowBytes
        )
    }

    mutating func freeSelf() {
        if data != nil {
            Darwin.free(data)   // ⬅️ Explicit global free
            data = nil
            height = 0
            width = 0
            rowBytes = 0
        }
    }
}
