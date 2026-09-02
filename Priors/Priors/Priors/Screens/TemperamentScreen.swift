//
//  TemperamentScreen.swift
//  Priors
//
//  Phase 3 — Self-report baseline prior.
//  Presents 4 interactive temperament cards (Careful, Curious, Generous, Steady)
//  capturing initial self-image while logging selection latency. SPEC §7, §8.
//

import SwiftUI
import PriorsEngine

public struct TemperamentScreen: View {
    public var onSelect: ((SelfImageLabel, Int) -> Void)?

    @State private var appearTime: ContinuousClock.Instant?
    @State private var selectedLabel: SelfImageLabel?

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    private struct TemperamentOption: Identifiable {
        let label: SelfImageLabel
        let icon: String
        let title: String
        let description: String
        var id: String { label.rawValue }
    }

    private let options: [TemperamentOption] = [
        TemperamentOption(
            label: .careful,
            icon: "shield.checkerboard",
            title: "Careful",
            description: "Measures every step and calculates the cost."
        ),
        TemperamentOption(
            label: .curious,
            icon: "sparkle.magnifyingglass",
            title: "Curious",
            description: "Ventures into the shadows to see what lies beyond."
        ),
        TemperamentOption(
            label: .generous,
            icon: "flame.fill",
            title: "Generous",
            description: "Shares the last spark with those in the cold."
        ),
        TemperamentOption(
            label: .steady,
            icon: "mountain.2.fill",
            title: "Steady",
            description: "Holds the path with unwavering resolve."
        )
    ]

    public init(onSelect: ((SelfImageLabel, Int) -> Void)? = nil) {
        self.onSelect = onSelect
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

                // Title & Subtitle Header
                VStack(spacing: 6) {
                    Text("Your traveller is —")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundColor(.white.opacity(0.95))

                    Text("Choose the inclination you bring into the dark.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.60))
                }

                // 4 Interactive Cards Row (Optimized for Landscape)
                HStack(spacing: 16) {
                    ForEach(options) { option in
                        Button(action: { handlePick(option.label) }) {
                            VStack(spacing: 12) {
                                // Icon in Circle Badge
                                ZStack {
                                    Circle()
                                        .fill(selectedLabel == option.label ? emberAccent.opacity(0.25) : Color.white.opacity(0.08))
                                        .frame(width: 44, height: 44)

                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(selectedLabel == option.label ? emberAccent : .white.opacity(0.85))
                                }
                                .padding(.top, 4)

                                // Card Title
                                Text(option.title)
                                    .font(.system(size: 16, weight: .semibold, design: .serif))
                                    .foregroundColor(.white.opacity(0.95))

                                // Evocative Subtitle Description
                                Text(option.description)
                                    .font(.system(size: 12, weight: .regular))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                                    .foregroundColor(.white.opacity(0.55))
                                    .frame(minHeight: 34)
                                    .padding(.horizontal, 4)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: 165, minHeight: 155)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedLabel == option.label ? cardBackground.opacity(0.95) : cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(
                                                selectedLabel == option.label
                                                    ? emberAccent.opacity(0.8)
                                                    : Color.white.opacity(0.12),
                                                lineWidth: selectedLabel == option.label ? 1.5 : 1
                                            )
                                    )
                                    .shadow(
                                        color: selectedLabel == option.label ? emberAccent.opacity(0.3) : Color.black.opacity(0.3),
                                        radius: selectedLabel == option.label ? 8 : 6,
                                        x: 0,
                                        y: 4
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("temperament_\(option.label.rawValue.lowercased())")
                    }
                }
                .frame(maxWidth: 720)

                Spacer()
            }
            .padding(.horizontal, 24)
            .safeAreaPadding()
        }
        .onAppear {
            if appearTime == nil {
                appearTime = ContinuousClock.now
            }
        }
    }

    private func handlePick(_ label: SelfImageLabel) {
        selectedLabel = label
        let now = ContinuousClock.now
        let ms: Int
        if let start = appearTime {
            let duration = start.duration(to: now)
            ms = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        } else {
            ms = 0
        }
        // Brief spring highlight feedback before callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelect?(label, ms)
        }
    }
}
