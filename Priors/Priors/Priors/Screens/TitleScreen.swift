//
//  TitleScreen.swift
//  Priors
//

import SwiftUI

public struct TitleScreen: View {
    /// SPEC §11 — composed from the strongest-confidence claim.
    ///
    /// Optional, because a session that produced no claim has no title, and the
    /// previous default ("The one who explored while it was free.") printed a
    /// line the player's own data had not earned. SPEC §2.1: nothing in the
    /// report is fictional. No claim, no title.
    public let title: String?
    public let onRestart: (() -> Void)?

    @State private var opacity: Double = 0
    @State private var showRestart = false

    public init(title: String?, onRestart: (() -> Void)? = nil) {
        self.title = title
        self.onRestart = onRestart
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                if let title {
                    Text(title)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // The session has an end. Without this the app simply stopped
                // here with nothing tappable.
                if showRestart, let onRestart {
                    Button(action: onRestart) {
                        Text("[ Begin again ]")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(minWidth: 120, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .padding(.bottom, 28)
                }
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) { opacity = 1 }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeIn(duration: 0.8)) { showRestart = true }
            }
        }
    }
}
