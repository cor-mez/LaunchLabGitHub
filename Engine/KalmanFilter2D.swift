//
//  KalmanFilter2D.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

/// 4-state linear Kalman filter (scalar math version)
///
/// x = [ px, py, vx, vy ]
///
/// State transition:
/// px' = px + vx*dt
/// py' = py + vy*dt
/// vx' = vx
/// vy' = vy
///
/// Measurement: [px, py]
///
final class KalmanFilter2D {

    // ---------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------

    // x = [px, py, vx, vy]
    private(set) var x = [Float](repeating: 0, count: 4)

    // 4×4 covariance
    private(set) var P = [[Float]](
        repeating: [Float](repeating: 1, count: 4),
        count: 4
    )

    // Process noise (4×4)
    private let Q: [[Float]] = [
        [0.05, 0,    0,    0   ],
        [0,    0.05, 0,    0   ],
        [0,    0,    0.1,  0   ],
        [0,    0,    0,    0.1 ]
    ]

    // Measurement noise (2×2)
    private let R: [[Float]] = [
        [1.5, 0   ],
        [0,   1.5 ]
    ]

    init(initialPos: CGPoint) {
        x[0] = Float(initialPos.x)
        x[1] = Float(initialPos.y)
        x[2] = 0
        x[3] = 0

        // Larger uncertainty on init
        for i in 0..<4 { P[i][i] = 10 }
    }

    // ---------------------------------------------------------
    // MARK: - Predict
    // ---------------------------------------------------------
    func predict(dt: Float) {

        // State transition matrix A
        // 4×4
        let A: [[Float]] = [
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1,  0],
            [0, 0, 0,  1]
        ]

        // x' = A·x
        var xNew = [Float](repeating: 0, count: 4)
        for i in 0..<4 {
            xNew[i] = A[i][0]*x[0] + A[i][1]*x[1] + A[i][2]*x[2] + A[i][3]*x[3]
        }
        x = xNew

        // P' = A·P·Aᵀ + Q
        var AP = Array(repeating: Array(repeating: Float(0), count: 4), count: 4)
        var APA = Array(repeating: Array(repeating: Float(0), count: 4), count: 4)

        // AP = A·P
        for i in 0..<4 {
            for j in 0..<4 {
                AP[i][j] =
                    A[i][0]*P[0][j] +
                    A[i][1]*P[1][j] +
                    A[i][2]*P[2][j] +
                    A[i][3]*P[3][j]
            }
        }

        // APA = AP·Aᵀ
        for i in 0..<4 {
            for j in 0..<4 {
                APA[i][j] =
                    AP[i][0]*A[j][0] +
                    AP[i][1]*A[j][1] +
                    AP[i][2]*A[j][2] +
                    AP[i][3]*A[j][3]
            }
        }

        // Add process noise
        for i in 0..<4 {
            for j in 0..<4 {
                P[i][j] = APA[i][j] + Q[i][j]
            }
        }
    }

    // ---------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------
    func update(measuredPos: CGPoint) {

        let z = [Float(measuredPos.x), Float(measuredPos.y)]

        // Measurement matrix H (2×4)
        // [1 0 0 0
        //  0 1 0 0]
        let H: [[Float]] = [
            [1, 0, 0, 0],
            [0, 1, 0, 0]
        ]

        // y = z - Hx  (innovation)
        let hx = [ x[0], x[1] ]
        let y = [ z[0] - hx[0], z[1] - hx[1] ]

        // S = HPHᵀ + R   (2×2)
        var HP = Array(repeating: Array(repeating: Float(0), count: 4), count: 2)
        var S  = Array(repeating: Array(repeating: Float(0), count: 2), count: 2)

        // HP = H·P (2×4)
        for i in 0..<2 {
            for j in 0..<4 {
                HP[i][j] =
                    H[i][0]*P[0][j] +
                    H[i][1]*P[1][j] +
                    H[i][2]*P[2][j] +
                    H[i][3]*P[3][j]
            }
        }

        // S = HP·Hᵀ + R  (2×2)
        for i in 0..<2 {
            for j in 0..<2 {
                S[i][j] =
                    HP[i][0]*H[j][0] +
                    HP[i][1]*H[j][1] +
                    HP[i][2]*H[j][2] +
                    HP[i][3]*H[j][3] +
                    R[i][j]
            }
        }

        // Invert S (2×2)
        let det = S[0][0]*S[1][1] - S[0][1]*S[1][0]
        if abs(det) < 1e-6 { return }

        let invS = [
            [  S[1][1]/det, -S[0][1]/det ],
            [ -S[1][0]/det,  S[0][0]/det ]
        ]

        // K = P Hᵀ S⁻¹ (4×2)
        var PHt = Array(repeating: Array(repeating: Float(0), count: 2), count: 4)
        var K   = Array(repeating: Array(repeating: Float(0), count: 2), count: 4)

        // PHt = P·Hᵀ
        for i in 0..<4 {
            for j in 0..<2 {
                PHt[i][j] =
                    P[i][0]*H[j][0] +
                    P[i][1]*H[j][1] +
                    P[i][2]*H[j][2] +
                    P[i][3]*H[j][3]
            }
        }

        // K = PHt·invS
        for i in 0..<4 {
            for j in 0..<2 {
                K[i][j] =
                    PHt[i][0]*invS[0][j] +
                    PHt[i][1]*invS[1][j]
            }
        }

        // x = x + K·y
        for i in 0..<4 {
            x[i] += K[i][0]*y[0] + K[i][1]*y[1]
        }

        // P = (I - K H) P
        var KH = Array(repeating: Array(repeating: Float(0), count: 4), count: 4)
        var IminusKH = Array(repeating: Array(repeating: Float(0), count: 4), count: 4)
        var newP = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)

        // KH = K·H
        for i in 0..<4 {
            for j in 0..<4 {
                KH[i][j] =
                    K[i][0]*H[0][j] +
                    K[i][1]*H[1][j]
            }
        }

        // I - KH
        for i in 0..<4 {
            for j in 0..<4 {
                IminusKH[i][j] = (i == j ? 1 : 0) - KH[i][j]
            }
        }

        // newP = (I-KH)·P
        for i in 0..<4 {
            for j in 0..<4 {
                newP[i][j] =
                    IminusKH[i][0]*P[0][j] +
                    IminusKH[i][1]*P[1][j] +
                    IminusKH[i][2]*P[2][j] +
                    IminusKH[i][3]*P[3][j]
            }
        }

        P = newP
    }

    // ---------------------------------------------------------
    // MARK: - Helpers
    // ---------------------------------------------------------
    var position: CGPoint {
        CGPoint(x: CGFloat(x[0]), y: CGFloat(x[1]))
    }

    var velocity: CGVector {
        CGVector(dx: CGFloat(x[2]), dy: CGFloat(x[3]))
    }

    func predictedPosition(dt: Float) -> CGPoint {
        CGPoint(
            x: CGFloat(x[0] + x[2] * dt),
            y: CGFloat(x[1] + x[3] * dt)
        )
    }
}
