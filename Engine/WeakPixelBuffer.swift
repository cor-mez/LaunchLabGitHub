import Foundation
import CoreVideo

final class WeakPixelBuffer {
    weak var buffer: CVPixelBuffer?
    init(_ buffer: CVPixelBuffer?) { self.buffer = buffer }
}
