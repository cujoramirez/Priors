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
        // SPEC §8.1 names step 0 "warm amber", step 3 "cool", step 4 "grey-blue".
        // Step 0 previously read r0.95/g0.82/b0.68 with a 6% vignette, which
        // over Kenney's (106,190,88) grass and its very saturated dirt is not
        // amber at all — it renders as flat midday green with a neon-orange
        // path. `saturation` is what tames that dirt, and until now nothing
        // read it (see `apply`).
        //
        // Step 0: Golden hour (> 0.20 SD) — low warm sun, olive grass, brick path
        PaletteStepAnchor(step: 0.0, hex: "#D89A4C", r: 0.92, g: 0.70, b: 0.52, saturation: 0.70, brightness: -0.12, contrast: 1.08),
        // Step 1: Last light (0.15–0.20 SD) — the amber going out of the sky
        PaletteStepAnchor(step: 1.0, hex: "#A9743E", r: 0.86, g: 0.66, b: 0.50, saturation: 0.62, brightness: -0.17, contrast: 1.07),
        // Step 2: Twilight (0.10–0.15 SD) — blue hour; warmth only near lanterns
        PaletteStepAnchor(step: 2.0, hex: "#6B6486", r: 0.70, g: 0.62, b: 0.72, saturation: 0.50, brightness: -0.24, contrast: 1.05),
        // Step 3: Cool (0.06–0.10 SD) — SPEC §8.1's named "cool"
        PaletteStepAnchor(step: 3.0, hex: "#454C61", r: 0.50, g: 0.54, b: 0.72, saturation: 0.36, brightness: -0.32, contrast: 1.02),
        // Step 4: Grey-blue night (< 0.06 SD) — SPEC §8.1's named "grey-blue"
        PaletteStepAnchor(step: 4.0, hex: "#252A36", r: 0.32, g: 0.36, b: 0.54, saturation: 0.20, brightness: -0.42, contrast: 1.00),
        // Step 5: Reading — room tone, the village all but gone
        PaletteStepAnchor(step: 5.0, hex: "#161A21", r: 0.18, g: 0.20, b: 0.32, saturation: 0.08, brightness: -0.52, contrast: 0.97),
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
        effectNode.filter = makeFilter(forStep: step)
        effectNode.shouldRasterize = false
        effectNode.shouldEnableEffects = true
    }

    /// Build the step's colour transform as a single `CIColorMatrix`.
    ///
    /// The anchor table has always carried `saturation` and `contrast`, and
    /// nothing ever read them: the old filter set only the diagonal, so it
    /// could tint and darken but never desaturate. That is why the dirt path
    /// rendered as neon orange no matter what the tint was — a warm tint on a
    /// very saturated source makes it worse, not duskier.
    ///
    /// All three fold into one 3x3 plus a bias, so this stays a single filter:
    ///   saturate  →  out = lum + s * (in - lum),  lum = 0.299R + 0.587G + 0.114B
    ///   contrast  →  out = (in - 0.5) * c + 0.5
    ///   tint      →  each output row scaled by its channel multiplier
    public func makeFilter(forStep step: Double) -> CIFilter? {
        let p = interpolatedParameters(forStep: step)
        guard let matrixFilter = CIFilter(name: "CIColorMatrix") else { return nil }

        let s = p.saturation
        let c = p.contrast
        let lr: CGFloat = 0.299, lg: CGFloat = 0.587, lb: CGFloat = 0.114
        let inv = 1.0 - s

        // Saturation rows, then contrast and the channel tint scale both the
        // row and the constant term.
        func row(_ tint: CGFloat, _ diagonal: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            (tint * c * (inv * lr + (diagonal == lr ? s : 0)),
             tint * c * (inv * lg + (diagonal == lg ? s : 0)),
             tint * c * (inv * lb + (diagonal == lb ? s : 0)))
        }
        let rr = row(p.r, lr), gg = row(p.g, lg), bb = row(p.b, lb)

        matrixFilter.setValue(CIVector(x: rr.0, y: rr.1, z: rr.2, w: 0), forKey: "inputRVector")
        matrixFilter.setValue(CIVector(x: gg.0, y: gg.1, z: gg.2, w: 0), forKey: "inputGVector")
        matrixFilter.setValue(CIVector(x: bb.0, y: bb.1, z: bb.2, w: 0), forKey: "inputBVector")

        // Contrast pivots around mid-grey, so it contributes its own constant.
        let pivot = 0.5 - 0.5 * c
        matrixFilter.setValue(
            CIVector(x: p.r * pivot + p.brightness,
                     y: p.g * pivot + p.brightness,
                     z: p.b * pivot + p.brightness,
                     w: 0),
            forKey: "inputBiasVector"
        )
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
