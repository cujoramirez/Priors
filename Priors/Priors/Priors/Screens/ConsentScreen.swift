//
//  ConsentScreen.swift
//  Priors
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

    public init(onStart: ((ConsentLog) -> Void)? = nil) {
        self.onStart = onStart
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Text("Priors records every choice you make and builds a model\nof how you decide.")
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)

                    Text("Everything stays on this device.")
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 48)

                Spacer()

                HStack(spacing: 48) {
                    Button(action: handleStart) {
                        Text("[ Start ]")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(minWidth: 100, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: handleOpenDetails) {
                        Text("[ What's collected ]")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(minWidth: 160, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .safeAreaPadding()

            if showingDetails {
                Color.black.opacity(0.96).ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    VStack(spacing: 14) {
                        Text("Every choice, and how long you took.\nWhere you walked, and where you stopped.\nWhat you did when nothing was watching.")
                            .font(.system(size: 16, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)

                        Text("None of it leaves this device.\nClose this and it still happens.")
                            .font(.system(size: 16, weight: .regular))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 48)

                    Spacer()

                    Button(action: handleCloseDetails) {
                        Text("[ Close ]")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .frame(minWidth: 100, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 32)
                .safeAreaPadding()
            }
        }
        .onAppear {
            if appearTime == nil {
                appearTime = ContinuousClock.now
            }
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
