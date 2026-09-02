//
//  SplashScreen.swift
//  Priors
//
//  The first thing on screen. An atmospheric title, a hold, a luminous fade.
//

import SwiftUI

public struct SplashScreen: View {
    public let onComplete: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var ruleWidth: CGFloat = 0

    private let hold: Duration = .milliseconds(2200)

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            roomToneBackground
                .ignoresSafeArea()

            // Subtle Ambient Breathing Glow
            RadialGradient(
                gradient: Gradient(colors: [
                    emberAccent.opacity(0.12),
                    Color.clear
                ]),
                center: .center,
                startRadius: 20,
                endRadius: 350
            )
            .opacity(glowOpacity)
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Priors")
                    .font(.system(size: 44, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .kerning(7)
                    .shadow(color: emberAccent.opacity(0.3), radius: 10, x: 0, y: 3)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                emberAccent.opacity(0.8),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: ruleWidth, height: 1.5)
            }
            .opacity(titleOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            withAnimation(.easeIn(duration: 1.0)) {
                titleOpacity = 1
                glowOpacity = 1
            }
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { ruleWidth = 200 }
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
        withAnimation(.easeOut(duration: 0.5)) {
            titleOpacity = 0
            glowOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(520))
            onComplete()
        }
    }
}
