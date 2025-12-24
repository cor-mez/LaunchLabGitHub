//
//  DotTestCoordinator+Accessors.swift
//

import CoreGraphics

extension DotTestCoordinator {

    /// Current ROI in full-frame coordinates
    func currentROI() -> CGRect {
        return lastROI
    }

    /// Full camera frame size
    func currentFullSize() -> CGSize {
        return lastFull
    }
}
