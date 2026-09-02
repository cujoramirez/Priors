//
//  ConsentScreen.swift
//  Priors
//
//  Phase 2 — Ethical transparency and informed consent.
//  Presents the data collection disclosure within an atmospheric frosted card
//  while accurately logging dwell times and details inspection. SPEC §8.
//

import SwiftUI
import Observation

@Observable
public final class ConsentLog: @unchecked Sendable {
    public var consentDwellMs: Int = 0
    public var consentReadDetails: Bool = false
    public var detailsDwellMs: Int? = nil

    public init(consentDwellMs: Int = 0, consentReadDetails: Bool = false, detailsDwellMs: Int? = nil) {
        self.consentDwellMs = consentDwellMs
        self.consentReadDetails = consentReadDetails
        self.detailsDwellMs = detailsDwellMs
    }
}

public struct ConsentScreen: View {
    @State public var log = ConsentLog()
    public var onStart: ((ConsentLog) -> Void)?

    @State private var appearTime: ContinuousClock.Instant?
    @State private var detailsOpenTime: ContinuousClock.Instant?
    @State private var showingDetails = false
    @State private var accumulatedDetailsMs: Int = 0

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    public init(onStart: ((ConsentLog) -> Void)? = nil) {
        self.onStart = onStart
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

            // Main Disclosure Card
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 20) {
                    // Header Badge
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(emberAccent)

                        Text("ETHICAL TRANSPARENCY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(emberAccent.opacity(0.9))
                            .kerning(1.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(emberAccent.opacity(0.12))
                            .overlay(Capsule().stroke(emberAccent.opacity(0.25), lineWidth: 1))
                    )

                    // Core Headline & Explanation
                    VStack(spacing: 12) {
                        Text("Priors records every choice you make\nand builds a model of how you decide.")
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .foregroundColor(.white.opacity(0.95))

                        Text("All telemetry, movement paths, and behavioral models\nremain strictly on this device.")
                            .font(.system(size: 14, weight: .regular))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .foregroundColor(.white.opacity(0.65))
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

                // Action Buttons Row
                HStack(spacing: 28) {
                    Button(action: handleStart) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(emberAccent)

                            Text("[ Start ]")
                                .font(.system(size: 16, weight: .medium, design: .serif))
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 130, minHeight: 44)
                        .padding(.horizontal, 16)
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
                    .accessibilityIdentifier("consentStartButton")

                    Button(action: handleOpenDetails) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))

                            Text("[ What's collected ]")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(minWidth: 170, minHeight: 44)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("consentDetailsButton")
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .safeAreaPadding()

            // Details Modal Overlay
            if showingDetails {
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 20) {
                    Spacer()

                    VStack(spacing: 22) {
                        // Modal Title
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(emberAccent)
                            Text("Data Collection Breakdown")
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.bottom, 4)

                        // 3 Categorized Detail Items
                        VStack(spacing: 14) {
                            detailRow(
                                icon: "timer",
                                title: "Choices & Decision Latencies",
                                description: "Every choice you make, and how many milliseconds you hesitated before deciding."
                            )

                            detailRow(
                                icon: "figure.walk",
                                title: "Movement & Exploration Paths",
                                description: "Where you walked, where you paused, and where you turned back along the road."
                            )

                            detailRow(
                                icon: "eye.slash",
                                title: "Unobserved Integrity Decisions",
                                description: "What you chose when nothing in the village appeared to be watching."
                            )
                        }

                        Divider()
                            .background(Color.white.opacity(0.12))

                        // Device Privacy Reassurance
                        VStack(spacing: 6) {
                            Text("None of it leaves this device.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))

                            Text("Close this and data recording continues locally.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 24 / 255.0, green: 28 / 255.0, blue: 38 / 255.0))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                    )

                    Spacer()

                    Button(action: handleCloseDetails) {
                        Text("[ Close ]")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundColor(.white)
                            .frame(minWidth: 120, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("consentCloseDetailsButton")
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 32)
                .safeAreaPadding()
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingDetails)
        .onAppear {
            if appearTime == nil {
                appearTime = ContinuousClock.now
            }
        }
    }

    private func detailRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(emberAccent.opacity(0.9))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))

                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.60))
                    .lineSpacing(2)
            }
            Spacer()
        }
    }

    private func handleStart() {
        let now = ContinuousClock.now
        if let start = appearTime {
            let duration = start.duration(to: now)
            log.consentDwellMs = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        }
        if showingDetails, let openTime = detailsOpenTime {
            let duration = openTime.duration(to: now)
            accumulatedDetailsMs += Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
            log.detailsDwellMs = accumulatedDetailsMs
        }
        onStart?(log)
    }

    private func handleOpenDetails() {
        log.consentReadDetails = true
        detailsOpenTime = ContinuousClock.now
        showingDetails = true
    }

    private func handleCloseDetails() {
        let now = ContinuousClock.now
        if let openTime = detailsOpenTime {
            let duration = openTime.duration(to: now)
            accumulatedDetailsMs += Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
            log.detailsDwellMs = accumulatedDetailsMs
            detailsOpenTime = nil
        }
        showingDetails = false
    }
}
