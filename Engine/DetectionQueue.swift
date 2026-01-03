//
//  DetectionQueue.swift
//  LaunchLab
//
//  Dedicated execution lane for vision + authority logic.
//  Keeps all heavy work off the MainActor.
//

import Foundation

enum DetectionQueue {
    static let shared = DispatchQueue(
        label: "launchlab.detection.queue",
        qos: .userInitiated
    )
}
