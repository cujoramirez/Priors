//
//  ReadingScreen.swift
//  Priors
//
//  Phase 5 — The Reading (8–12 screens, tap-advance, no skip, verbatim copy).
//  SPEC §7, §9.
//

import SwiftUI
import PriorsEngine

public struct ReadingScreen: View {
    public let claims: [Claim]
    public let onComplete: ([Claim]) -> Void

    @State private var currentIndex: Int = 0
    @State private var opacity: Double = 0.0

    // Dark room tone palette step 5 (SPEC §8.1)
    private let roomToneBackground = Color(red: 26.0 / 255.0, green: 29.0 / 255.0, blue: 36.0 / 255.0)

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

    /// The claims that can actually be read, paired with their copy.
    ///
    /// SPEC §2.1 — a claim missing a value it interpolates must not render. The
    /// reading has no skip, so an unrenderable claim cannot simply draw nothing:
    /// it would leave a blank screen with no tap target and strand the player.
    /// It is dropped from the sequence instead, and never reaches the argument
    /// screen either — you can only dispute what you were told.
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

            if let page = currentPage {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer()

                    Text(page.body)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundColor(.white.opacity(0.92))
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 48)

                    Spacer()

                    // Subtle hint on bottom edge
                    HStack {
                        Spacer()
                        Text("[ Tap to continue ]")
                            .font(.system(size: 13, weight: .light, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
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
