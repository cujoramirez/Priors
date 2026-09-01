//
//  PaletteController.swift
//  Priors
//

import SpriteKit
import CoreImage
import SwiftUI

/// SPEC §8.1 — Palette anchors and continuous dusk colour transform.
public struct PaletteStepAnchor: Sendable {
    public let step: Double
    public let hex: String
    public let r: CGFloat
    public let g: CGFloat
    public let b: CGFloat
    public let saturation: CGFloat
    public let brightness: CGFloat
    public let contrast: CGFloat

    public init(step: Double, hex: String, r: CGFloat, g: CGFloat, b: CGFloat, saturation: CGFloat, brightness: CGFloat, contrast: CGFloat) {
        self.step = step
        self.hex = hex
        self.r = r
        self.g = g
        self.b = b
        self.saturation = saturation
        self.brightness = brightness
        self.contrast = contrast
    }
}

public final class PaletteController: @unchecked Sendable {
    /// Clearly marked palette anchors table (SPEC §8.1)
    public static let anchors: [PaletteStepAnchor] = [
        // Step 0: Atmospheric warm dusk (> 0.20 SD) - rich shadows, warm amber dusk tone
        PaletteStepAnchor(step: 0.0, hex: "#D49B55", r: 0.95, g: 0.82, b: 0.68, saturation: 0.98, brightness: -0.08, contrast: 1.06),
        // Step 1: Fading warm amber (0.15–0.20 SD) - dusk settling into twilight
        PaletteStepAnchor(step: 1.0, hex: "#A67B5B", r: 0.84, g: 0.72, b: 0.65, saturation: 0.88, brightness: -0.15, contrast: 1.05),
        // Step 2: Twilight violet / slate (0.10–0.15 SD) - deep blue-grey twilight
        PaletteStepAnchor(step: 2.0, hex: "#5C5B77", r: 0.70, g: 0.64, b: 0.78, saturation: 0.72, brightness: -0.22, contrast: 1.03),
        // Step 3: Cool deep slate (0.06–0.10 SD) - dark dusk blue
        PaletteStepAnchor(step: 3.0, hex: "#3B4252", r: 0.52, g: 0.56, b: 0.76, saturation: 0.55, brightness: -0.30, contrast: 1.00),
        // Step 4: Dark nightfall (< 0.06 SD) - moody near-night
        PaletteStepAnchor(step: 4.0, hex: "#242933", r: 0.36, g: 0.40, b: 0.58, saturation: 0.36, brightness: -0.40, contrast: 0.98),
        // Step 5: Reading (dark room tone / pure focus)
        PaletteStepAnchor(step: 5.0, hex: "#1A1D24", r: 0.20, g: 0.22, b: 0.32, saturation: 0.12, brightness: -0.50, contrast: 0.95),
    ]

    public init() {}

    /// Map mean posterior SD to continuous palette step [0.0, 5.0] per SPEC §8.1.
    public func step(forMeanPosteriorSD sd: Double) -> Double {
        if sd >= 0.25 {
            return 0.0
        } else if sd >= 0.20 {
            // [0.25 -> 0.0, 0.20 -> 1.0]
            let t = (0.25 - sd) / (0.25 - 0.20)
            return t * 1.0
        } else if sd >= 0.15 {
            // [0.20 -> 1.0, 0.15 -> 2.0]
            let t = (0.20 - sd) / (0.20 - 0.15)
            return 1.0 + t * 1.0
        } else if sd >= 0.10 {
            // [0.15 -> 2.0, 0.10 -> 3.0]
            let t = (0.15 - sd) / (0.15 - 0.10)
            return 2.0 + t * 1.0
        } else if sd >= 0.06 {
            // [0.10 -> 3.0, 0.06 -> 4.0]
            let t = (0.10 - sd) / (0.10 - 0.06)
            return 3.0 + t * 1.0
        } else if sd > 0.0 {
            // [0.06 -> 4.0, 0.0 -> 5.0]
            let t = (0.06 - sd) / 0.06
            return 4.0 + t * 1.0
        } else {
            return 5.0
        }
    }

    /// Interpolate parameters for a continuous palette step in [0.0, 5.0].
    public func interpolatedParameters(forStep step: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat, saturation: CGFloat, brightness: CGFloat, contrast: CGFloat) {
        let clamped = max(0.0, min(5.0, step))
        let lowerIdx = Int(floor(clamped))
        let upperIdx = min(Self.anchors.count - 1, lowerIdx + 1)
        let fraction = CGFloat(clamped - Double(lowerIdx))

        let a = Self.anchors[lowerIdx]
        let b = Self.anchors[upperIdx]

        let r = a.r + (b.r - a.r) * fraction
        let g = a.g + (b.g - a.g) * fraction
        let blue = a.b + (b.b - a.b) * fraction
        let saturation = a.saturation + (b.saturation - a.saturation) * fraction
        let brightness = a.brightness + (b.brightness - a.brightness) * fraction
        let contrast = a.contrast + (b.contrast - a.contrast) * fraction

        return (r, g, blue, saturation, brightness, contrast)
    }

    /// Apply color filter parameters to an SKEffectNode for runtime continuous color transform.
    public func apply(to effectNode: SKEffectNode, step: Double) {
        let p = interpolatedParameters(forStep: step)

        guard let matrixFilter = CIFilter(name: "CIColorMatrix") else { return }
        matrixFilter.setValue(CIVector(x: p.r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrixFilter.setValue(CIVector(x: 0, y: p.g, z: 0, w: 0), forKey: "inputGVector")
        matrixFilter.setValue(CIVector(x: 0, y: 0, z: p.b, w: 0), forKey: "inputBVector")
        matrixFilter.setValue(CIVector(x: p.brightness, y: p.brightness, z: p.brightness, w: 0), forKey: "inputBiasVector")

        effectNode.filter = matrixFilter
        effectNode.shouldRasterize = false
        effectNode.shouldEnableEffects = true
    }

    /// Create a CIFilter chain directly for a given step.
    public func makeFilter(forStep step: Double) -> CIFilter? {
        let p = interpolatedParameters(forStep: step)
        guard let matrixFilter = CIFilter(name: "CIColorMatrix") else { return nil }
        matrixFilter.setValue(CIVector(x: p.r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrixFilter.setValue(CIVector(x: 0, y: p.g, z: 0, w: 0), forKey: "inputGVector")
        matrixFilter.setValue(CIVector(x: 0, y: 0, z: p.b, w: 0), forKey: "inputBVector")
        matrixFilter.setValue(CIVector(x: p.brightness, y: p.brightness, z: p.brightness, w: 0), forKey: "inputBiasVector")
        return matrixFilter
    }
}

/// Acceptance demo view with a slider driving paletteStep 0 -> 5 continuously.
public struct PaletteDemoView: View {
    @State private var paletteStep: Double = 0.0
    private let controller = PaletteController()

    public init() {}

    public var body: some View {
        let p = controller.interpolatedParameters(forStep: paletteStep)

        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Palette Decay Demo (SPEC §8.1)")
                    .font(.headline)
                    .foregroundColor(.white)

                // Color swatch representing current interpolated palette
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: Double(p.r * 0.8), green: Double(p.g * 0.8), blue: Double(p.b * 0.8)))
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            Text("Step: \(paletteStep, specifier: "%.2f")")
                                .font(.title3)
                                .bold()
                            Text("Sat: \(p.saturation, specifier: "%.2f") Bright: \(p.brightness, specifier: "%.2f")")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    )
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Palette Step: \(paletteStep, specifier: "%.2f") / 5.0")
                        .foregroundColor(.white)
                        .font(.subheadline)

                    Slider(value: $paletteStep, in: 0.0...5.0)
                        .tint(.white)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
