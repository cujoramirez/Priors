//
//  TemperamentScreen.swift
//  Priors
//

import SwiftUI
import PriorsEngine

public struct TemperamentScreen: View {
    public var onSelect: ((SelfImageLabel, Int) -> Void)?

    @State private var appearTime: ContinuousClock.Instant?

    public init(onSelect: ((SelfImageLabel, Int) -> Void)? = nil) {
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("Your traveller is —")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.white)

                HStack(spacing: 36) {
                    Button(action: { handlePick(.careful) }) {
                        Text("Careful")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                            .frame(minWidth: 80, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { handlePick(.curious) }) {
                        Text("Curious")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                            .frame(minWidth: 80, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { handlePick(.generous) }) {
                        Text("Generous")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                            .frame(minWidth: 80, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { handlePick(.steady) }) {
                        Text("Steady")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.white)
                            .frame(minWidth: 80, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
            .safeAreaPadding()
        }
        .onAppear {
            if appearTime == nil {
                appearTime = ContinuousClock.now
            }
        }
    }

    private func handlePick(_ label: SelfImageLabel) {
        let now = ContinuousClock.now
        let ms: Int
        if let start = appearTime {
            let duration = start.duration(to: now)
            ms = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        } else {
            ms = 0
        }
        onSelect?(label, ms)
    }
}
