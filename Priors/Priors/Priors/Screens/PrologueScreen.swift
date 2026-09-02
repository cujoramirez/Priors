//
//  PrologueScreen.swift
//  Priors
//
//  Cinematic 3-page narrative prologue establishing the mythos of Aethelmere,
//  the Long Freeze, and the role of the Vigil Runner before entering the village.
//

import SwiftUI

public struct PrologueScreen: View {
    public var onComplete: (() -> Void)?

    @State private var currentPage: Int = 0

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    public static let pages: [String] = [
        "The sun set three years ago.\nSince then, the valley of Aethelmere has lived on carried fire.\n\nEvery evening, when the iron bell tolls from the Great Hearth,\na Runner takes the brass lanterns into the dusk.",
        "Tonight is the Long Freeze.\nThe wind from the northern crags is bitter, and the oil is low.\n\nThere are families waiting in the lower lanes whose windows have already iced over.\nYou carry three lanterns. It is not enough for everyone.",
        "Move swiftly. Do not let your own light gutter in the cold.\n\nWhat you give, and what you keep, is between you and the dark."
    ]

    public init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Atmospheric Background with Subtle Radial Ambient Warmth
            roomToneBackground
                .ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [emberAccent.opacity(0.10), Color.clear]),
                center: .leading,
                startRadius: 20,
                endRadius: 620
            )
            .ignoresSafeArea()

            // Landscape-native two-column layout.
            //
            // This screen was a tall VStack — badge, a 180pt-minimum text
            // block, Spacers, dots and a 44pt button — needing well over 600pt
            // of height. The app is landscape-only (Info.plist lists only
            // LandscapeLeft/Right), which gives roughly 390pt. SwiftUI resolved
            // the overflow by compressing the Text, so the prologue rendered
            // with its sentences cut off mid-clause ("...the Great Hearth,…")
            // and the button clipped off the bottom edge. There was no
            // `lineLimit` anywhere; it was pure vertical overflow.
            //
            // The wide axis is the one there is room on, so the identity rail
            // (badge, progress, action) moves to the left and the narrative
            // takes the rest. `fixedSize` guarantees the Text reports its full
            // height and is never compressed again.
            HStack(alignment: .center, spacing: 28) {
                identityRail
                    .frame(width: 210)

                narrativePlate
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .safeAreaPadding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            advancePage()
        }
        .accessibilityIdentifier("prologueScreen")
    }

    /// Left rail: what chapter this is, how far through it you are, and the
    /// way onward. Everything that is not the story itself.
    private var identityRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(emberAccent)

                Text("THE PROLOGUE")
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

            Text("Nightfall")
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundColor(.white.opacity(0.92))

            HStack(spacing: 10) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? emberAccent : Color.white.opacity(0.20))
                        .frame(width: index == currentPage ? 8 : 6,
                               height: index == currentPage ? 8 : 6)
                        .shadow(color: index == currentPage ? emberAccent.opacity(0.5) : Color.clear, radius: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            actionButton
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if currentPage < Self.pages.count - 1 {
            Button(action: { advancePage() }) {
                Text("[ Continue ]")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prologueNext")
        } else {
            Button(action: { handleBeginVigil() }) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(emberAccent)

                    Text("[ Begin the Vigil ]")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(emberAccent.opacity(0.5), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("enterVigilButton")
        }
    }

    /// The story itself. `fixedSize(vertical:)` is the guard against the
    /// truncation this layout was rebuilt to fix; the ScrollView is the
    /// fallback for accessibility text sizes that outgrow even this.
    private var narrativePlate: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    if index == currentPage {
                        Text(Self.pages[index])
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundColor(Color.white.opacity(0.95))
                            .multilineTextAlignment(.leading)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                            .id(index)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
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
    }

    private func advancePage() {
        if currentPage < Self.pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.45)) {
                currentPage += 1
            }
        }
    }

    private func handleBeginVigil() {
        onComplete?()
    }
}
