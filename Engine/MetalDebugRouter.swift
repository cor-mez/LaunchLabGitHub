import Foundation
import MetalKit

enum DotTestDebugSurface {
    case yNorm
    case yEdge
    case cbEdge
    case fast9y
    case fast9cb
    case roi
}

final class MetalDebugRouter {

    static let shared = MetalDebugRouter()

    func draw(_ surface: DotTestDebugSurface, in view: MTKView) {
        MetalRenderer.shared.routeDebugSurface(surface, in: view)
    }
}