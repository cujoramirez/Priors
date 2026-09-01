//
//  SelfPredictionScreen.swift
//  Priors
//

import SwiftUI

public struct SelfPredictionScreen: View {
    public var onConfirm: ((Double) -> Void)?

    @State private var sliderValue: Double = 50.0

    public init(onConfirm: ((Double) -> Void)? = nil) {
        self.onConfirm = onConfirm
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("Before the paths —\nhow much risk would you have accepted?")
                    .font(.system(size: 18, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)

                VStack(spacing: 14) {
                    // The player is being asked for a percentage and could not
                    // see which one they had chosen: the track showed a thumb
                    // and nothing else. The number is the answer they are
                    // giving, and it is logged as `self_predicted_theta_e`.
                    Text("\(Int(sliderValue.rounded()))%")
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .accessibilityIdentifier("selfPredictionValue")

                    HStack(spacing: 16) {
                        Text("0%")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.gray)
                            .frame(width: 44, alignment: .trailing)

                        RiskSlider(value: $sliderValue)

                        Text("100%")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.gray)
                            .frame(width: 44, alignment: .leading)
                    }
                    .frame(maxWidth: 480)
                }

                Spacer()

                Button(action: handleConfirm) {
                    Text("[ Continue ]")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .frame(minWidth: 120, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selfPredictionContinue")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 40)
            .safeAreaPadding()
        }
    }

    private func handleConfirm() {
        let normalized = sliderValue / 100.0
        onConfirm?(normalized)
    }
}

/// A slider whose whole track responds.
///
/// SwiftUI's `Slider` only reacts to a drag that begins on the thumb: pressing
/// anywhere else on the track does nothing, and a UI test dragging from the
/// middle of the track left the value untouched. On a screen whose entire
/// purpose is capturing one number, hunting for a 22pt thumb is the wrong
/// interaction — and the number it captures is what COPY R5 reads back as
/// "You said {self_pred_pct}%", so being unable to set it precisely corrupts a
/// headline claim.
///
/// Tap or drag anywhere on the track; both ends are reachable because the
/// fraction is clamped rather than inset by half a thumb.
struct RiskSlider: View {
    @Binding var value: Double          // 0...100

    private let thumb: CGFloat = 22
    private let track: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = min(max(value / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: track)
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * fraction, height: track)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .offset(x: width * fraction - thumb / 2)
            }
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(g.location.x / width, 0), 1)
                        value = (f * 100).rounded()
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityIdentifier("selfPredictionSlider")
        .accessibilityLabel("Risk you would have accepted")
        .accessibilityValue("\(Int(value.rounded()))%")
        // Adjustable rather than a button: VoiceOver users can set the value
        // without needing to land a drag on a 22pt target either.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(100, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}
