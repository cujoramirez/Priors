//
//  SplashScreen.swift
//  Priors
//
//  The first thing on screen. A title, a hold, a fade.
//
//  Deliberately austere: SPEC §2.4 forbids a named protagonist and §2 forbids
//  encouragement, so there is no tagline, no logo animation and no "tap to
//  play" urging. It exists to give the app a beginning rather than snapping
//  straight to a consent form, and to cover the first frame while SpriteKit
//  and the audio engine warm up.
//

import SwiftUI

public struct SplashScreen: View {
    public let onComplete: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var ruleWidth: CGFloat = 0

    /// Total time on screen. Long enough to read, short enough not to annoy on
    /// a replay — and skippable by tapping.
    private let hold: Duration = .milliseconds(2200)

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Priors")
                    .font(.system(size: 42, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .kerning(6)

                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: ruleWidth, height: 1)
            }
            .opacity(titleOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            withAnimation(.easeIn(duration: 1.0)) { titleOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { ruleWidth = 180 }
            Task {
                try? await Task.sleep(for: hold)
                finish()
            }
        }
    }

    @State private var finished = false

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeOut(duration: 0.5)) { titleOpacity = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(520))
            onComplete()
        }
    }
}
