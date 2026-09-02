//
//  TitleScreen.swift
//  Priors
//
//  SPEC §11 — Final title screen composed from the strongest-confidence claim.
//

import SwiftUI

public struct TitleScreen: View {
    public let title: String?
    public let onRestart: (() -> Void)?

    @State private var opacity: Double = 0
    @State private var showRestart = false

    // Design Tokens
    private let roomToneBackground = Color(red: 20 / 255.0, green: 23 / 255.0, blue: 31 / 255.0)
    private let emberAccent = Color(red: 232 / 255.0, green: 141 / 255.0, blue: 56 / 255.0)
    private let cardBackground = Color(red: 28 / 255.0, green: 32 / 255.0, blue: 44 / 255.0).opacity(0.85)

    public init(title: String?, onRestart: (() -> Void)? = nil) {
        self.title = title
        self.onRestart = onRestart
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

            VStack(spacing: 36) {
                Spacer()

                if let title {
                    VStack(spacing: 16) {
                        // Chronicle Badge Header
                        Text("THE CHRONICLE OF THE VIGIL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(emberAccent.opacity(0.85))
                            .kerning(2)

                        // The Earned Title
                        Text("“\(title)”")
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 32)
                            .shadow(color: emberAccent.opacity(0.25), radius: 8, x: 0, y: 2)
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 580)
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

                Spacer()

                if showRestart, let onRestart {
                    Button(action: onRestart) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))

                            Text("[ Begin again ]")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .frame(minWidth: 140, minHeight: 44)
                        .padding(.horizontal, 16)
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
                    .transition(.opacity)
                    .padding(.bottom, 24)
                }
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) { opacity = 1 }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeIn(duration: 0.8)) { showRestart = true }
            }
        }
    }
}
