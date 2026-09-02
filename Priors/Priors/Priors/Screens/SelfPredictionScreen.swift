//
//  SelfPredictionScreen.swift
//  Priors
//
//  Phase 4 — Predicting own behavior under risk.
//  Presents the self-prediction slider inside an atmospheric frosted card
//  with illuminated percentage readout and gradient risk track. SPEC §7, §8.
//

import SwiftUI

public struct SelfPredictionScreen: View {
    public var onConfirm: ((Double) -> Void)?

    @State private var sliderValue: Double = 50.0

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    public init(onConfirm: ((Double) -> Void)? = nil) {
        self.onConfirm = onConfirm
    }

    public var body: some View {
        ZStack {
            // Atmospheric Background with Subtle Radial Ambient Warmth
            roomToneBackground
                .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    emberAccent.opacity(0.08),
                    Color.clear
                ]),
                center: .center,
                startRadius: 20,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Centered Frosted Prediction Card
                VStack(spacing: 22) {
                    // Header Title & Explainer
                    VStack(spacing: 8) {
                        // Landscape-only app, portrait-height card: without
                        // `fixedSize(vertical:)` SwiftUI compresses this to
                        // one line and the question itself is elided to
                        // "Before the paths —…", leaving the player to answer
                        // a prompt they were never shown.
                        Text("Before the paths —\nhow much risk would you have accepted?")
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.white.opacity(0.95))

                        Text("Estimate your threshold for navigating danger when fuel is low.")
                            .font(.system(size: 13, weight: .regular))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(.white.opacity(0.60))
                    }

                    // Large Glowing Value Readout
                    VStack(spacing: 12) {
                        Text("\(Int(sliderValue.rounded()))%")
                            .font(.system(size: 34, weight: .light, design: .serif))
                            .foregroundColor(emberAccent.opacity(0.95))
                            .monospacedDigit()
                            .accessibilityIdentifier("selfPredictionValue")
                            .shadow(color: emberAccent.opacity(0.35), radius: 8, x: 0, y: 2)

                        HStack(spacing: 16) {
                            Text("0%")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.40))
                                .frame(width: 44, alignment: .trailing)

                            RiskSlider(value: $sliderValue)

                            Text("100%")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.40))
                                .frame(width: 44, alignment: .leading)
                        }
                        .frame(maxWidth: 460)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                )

                Spacer()

                // Action Continue Button
                Button(action: handleConfirm) {
                    Text("[ Continue ]")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .frame(minWidth: 140, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(emberAccent.opacity(0.4), lineWidth: 1)
                                )
                        )
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

/// A slider whose whole track responds with illuminated glowing progress.
struct RiskSlider: View {
    @Binding var value: Double // 0...100

    private let thumb: CGFloat = 22
    private let trackHeight: CGFloat = 6

    // Accent Colors
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = min(max(value / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: trackHeight)

                // Illuminated Active Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                emberAccent.opacity(0.9),
                                Color.orange
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * fraction, height: trackHeight)

                // Glowing Thumb
                ZStack {
                    Circle()
                        .fill(emberAccent.opacity(0.35))
                        .frame(width: thumb + 8, height: thumb + 8)

                    Circle()
                        .fill(Color.white)
                        .frame(width: thumb, height: thumb)
                        .overlay(Circle().stroke(emberAccent.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
                .offset(x: width * fraction - (thumb + 8) / 2.0)
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
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(100, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}
