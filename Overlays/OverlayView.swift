//
//  OverlayView.swift
//  LaunchLab
//

import SwiftUI

struct OverlayView: UIViewRepresentable {

    let layers: [BaseOverlayLayer]

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false

        for layer in layers {
            v.layer.addSublayer(layer)
        }

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        for layer in layers {
            layer.frame = uiView.bounds
            layer.setNeedsDisplay()
        }
    }
}
