//
//  ReadingScreen.swift
//  Priors
//
//  Phase 5 — The Reading (8–12 screens, tap-advance, no skip, verbatim copy).
//  Presents psychological claim observations inside an atmospheric frosted card
//  with illuminated progression tracking. SPEC §7, §9.
//

import SwiftUI
import PriorsEngine

public struct ReadingScreen: View {
    public let claims: [Claim]
    public let onComplete: ([Claim]) -> Void

    @State private var currentIndex: Int = 0
    @State private var opacity: Double = 0.0

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    public init(
        claims: [Claim],
        onComplete: @escaping ([Claim]) -> Void
    ) {
        self.claims = claims
        self.onComplete = onComplete
    }

    /// One reading screen: a claim and the copy it renders to.
    public struct Page: Identifiable {
        public let claim: Claim
        public let body: String
        public var id: String { claim.id }
    }

    public static func pages(for claims: [Claim]) -> [Page] {
        claims.compactMap { claim in
            ClaimRenderer.render(claim: claim).map { Page(claim: claim, body: $0) }
        }
    }

    private var pages: [Page] { Self.pages(for: claims) }

    private var currentPage: Page? {
        let p = pages
        guard currentIndex >= 0 && currentIndex < p.count else { return nil }
        return p[currentIndex]
    }

    public var body: some View {
        ZStack {
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

            if let page = currentPage {
                VStack(spacing: 24) {
                    Spacer()

                    // Observation Card Container
                    VStack(alignment: .leading, spacing: 18) {
                        // Header Badge with Progress Counter
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(emberAccent)
                                    .frame(width: 6, height: 6)

                                Text("OBSERVATION \(currentIndex + 1) OF \(pages.count)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(emberAccent.opacity(0.9))
                                    .kerning(1.5)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(emberAccent.opacity(0.12))
                                    .overlay(Capsule().stroke(emberAccent.opacity(0.25), lineWidth: 1))
                            )

                            Spacer()
                        }

                        // Verbatim Claim Copy
                        Text(page.body)
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 30)
                    .frame(maxWidth: 620)
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

                    // Subtle Tap Hint on Bottom Edge
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Text("Tap to continue")
                                .font(.system(size: 13, weight: .light, design: .monospaced))
                                .foregroundColor(.white.opacity(0.40))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.30))
                        }
                        .padding(.bottom, 24)
                        .padding(.trailing, 48)
                    }
                }
                .opacity(opacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    advance()
                }
            }
        }
        .onAppear {
            AudioManager.shared.enterReadingRoomTone()
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1.0
            }
        }
    }

    private func advance() {
        if currentIndex + 1 < pages.count {
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                currentIndex += 1
                withAnimation(.easeIn(duration: 0.4)) {
                    opacity = 1.0
                }
            }
        } else {
            onComplete(pages.map(\.claim))
        }
    }
}
