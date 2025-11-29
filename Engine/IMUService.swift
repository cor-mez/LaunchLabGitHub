// File: Engine/IMUService.swift
//
//  IMUService.swift
//  LaunchLab
//

import Foundation
import CoreMotion
import simd

struct IMUState {
    var gravity: SIMD3<Float>
    var rotationRate: SIMD3<Float>
    var attitude: simd_quatf

    static let zero = IMUState(
        gravity: SIMD3<Float>(0, -1, 0),
        rotationRate: SIMD3<Float>(repeating: 0),
        attitude: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    )
}

final class IMUService: NSObject, ObservableObject {

    static let shared = IMUService()

    @Published private(set) var currentState: IMUState = .zero

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.launchlab.imu.queue"
        q.qualityOfService = .userInteractive
        return q
    }()

    override private init() {
        super.init()
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 200.0

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }

            let g = motion.gravity
            let rr = motion.rotationRate
            let q = motion.attitude.quaternion

            let gravity = SIMD3<Float>(Float(g.x), Float(g.y), Float(g.z))
            let rotationRate = SIMD3<Float>(Float(rr.x), Float(rr.y), Float(rr.z))
            let attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))

            let state = IMUState(
                gravity: gravity,
                rotationRate: rotationRate,
                attitude: attitude
            )

            DispatchQueue.main.async {
                self.currentState = state
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
