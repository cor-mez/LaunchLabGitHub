//
//  RefusalReason.swift
//  LaunchLab
//
//  Canonical refusal reasons (V1)
//

import Foundation

enum RefusalReason: String {
    case none
    case mdgRevoked
    case insufficientConfidence
    case trackingLost
    case invalidMotion
    case timeout
    case unknown
}
