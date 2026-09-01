//
//  ArgumentScreen.swift
//  Priors
//
//  Phase 6 — The Argument screen (SPEC §10, COPY.md).
//  Player selects a claim to dispute, machine shows receipts and refits posterior.
//

import SwiftUI
import PriorsEngine

public struct ArgumentScreen: View {
    public let sessionRecord: SessionRecord
    public let claims: [Claim]
    public let onComplete: (SessionRecord) -> Void

    @State private var selectedClaim: Claim?
    @State private var activeReason: ArgumentEvent.Reason?
    @State private var refitPosterior: PosteriorSnapshot?
    @State private var dualHypothesisFastChoice: Bool?
    @State private var argumentEvents: [ArgumentEvent] = []

    // Dark room tone
    private let roomToneBackground = Color(red: 26.0 / 255.0, green: 29.0 / 255.0, blue: 36.0 / 255.0)

    public init(
        sessionRecord: SessionRecord,
        claims: [Claim],
        onComplete: @escaping (SessionRecord) -> Void
    ) {
        self.sessionRecord = sessionRecord
        self.claims = claims
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            roomToneBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                if selectedClaim == nil {
                    // Claim Selection View
                    Text("Which of these is wrong?")
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .padding(.top, 28)
                        .padding(.horizontal, 36)

                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(ReadingScreen.pages(for: claims)) { page in
                                Button {
                                    withAnimation {
                                        selectedClaim = page.claim
                                    }
                                } label: {
                                    HStack {
                                        Text(page.body)
                                            .font(.system(size: 15, weight: .regular, design: .serif))
                                            .foregroundColor(.white.opacity(0.88))
                                            .multilineTextAlignment(.leading)
                                            .lineSpacing(4)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white.opacity(0.4))
                                            .font(.system(size: 14))
                                    }
                                    .padding(16)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.bottom, 24)
                    }

                    HStack {
                        Spacer()
                        Button("[ None of them ]") {
                            finishArgument()
                        }
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.bottom, 20)
                        .padding(.trailing, 36)
                    }
                } else if let claim = selectedClaim, activeReason == nil {
                    // Receipts & "Why was I wrong?" View
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Button {
                                withAnimation {
                                    selectedClaim = nil
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Back to claims")
                                }
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 20)

                            // Selection only ever comes from a renderable page,
                            // so this unwrap always succeeds; it is written as a
                            // conditional rather than a default so a missing
                            // value can never print as invented copy.
                            if let body = ClaimRenderer.render(claim: claim) {
                                Text(body)
                                    .font(.system(size: 17, weight: .medium, design: .serif))
                                    .foregroundColor(.white)
                                    .lineSpacing(6)
                            }

                            Divider().background(Color.white.opacity(0.2))

                            // Supporting Receipts
                            Text("Supporting observations:")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))

                            let supportingDecisions = sessionRecord.decisions.filter { claim.supportingDecisionIDs.contains($0.index) }
                            VStack(spacing: 8) {
                                ForEach(supportingDecisions) { d in
                                    HStack {
                                        Text("Decision #\(d.index + 1) (\(d.template.rawValue.uppercased()))")
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text("Price: \(Int(d.price * 100))% • \(d.engaged ? "Went in" : "Declined") • \(String(format: "%.1f", d.rtSeconds))s")
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(6)
                                }
                            }

                            Text("Why was I wrong?")
                                .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundColor(.white)
                                .padding(.top, 10)

                            VStack(spacing: 12) {
                                argumentButton("The situation was different") {
                                    applyReason(.situation, for: claim)
                                }
                                argumentButton("I misread it") {
                                    applyReason(.misread, for: claim)
                                }
                                argumentButton("That wasn't really me") {
                                    applyReason(.notMe, for: claim)
                                }
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.bottom, 32)
                    }
                } else if let claim = selectedClaim, let reason = activeReason {
                    // Concession / Dual-Hypothesis View
                    VStack(alignment: .leading, spacing: 24) {
                        Spacer()

                        if reason == .situation || reason == .misread {
                            let snapshot = refitPosterior ?? sessionRecord.finalPosterior
                            let traitName = (claim.kind == .moralLine) ? "Your moral threshold" : "Your exploration line"
                            let meanVal = Int(((claim.kind == .moralLine) ? snapshot.thetaIMean : snapshot.thetaEMean) * 100)
                            let sdVal = Int(((claim.kind == .moralLine) ? snapshot.thetaISD : snapshot.thetaESD) * 100)

                            Text("""
                            Then I'm less sure than I was.
                            \(traitName) moves to \(meanVal)%, ±\(sdVal)%.

                            That's the honest version.
                            """)
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .foregroundColor(.white.opacity(0.92))
                            .lineSpacing(8)

                            Spacer()

                            HStack {
                                Spacer()
                                Button("[ Continue ]") {
                                    finishArgument()
                                }
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.bottom, 24)
                                .padding(.trailing, 36)
                            }
                        } else if reason == .notMe {
                            let (fastRT, slowRT, nConsistent) = computeDualHypothesisMetrics()

                            Text("""
                            Then I have two versions of you and they disagree.

                            One decided in \(String(format: "%.1f", fastRT)) seconds and was consistent for \(nConsistent) decisions.

                            The other decided in \(String(format: "%.1f", slowRT)) seconds and was consistent with nothing.

                            Which one would you like me to believe?
                            """)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundColor(.white.opacity(0.92))
                            .lineSpacing(8)

                            Spacer()

                            HStack(spacing: 24) {
                                Spacer()
                                Button("[ The fast one ]") {
                                    dualHypothesisFastChoice = true
                                    finishArgument()
                                }
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)

                                Button("[ The slow one ]") {
                                    dualHypothesisFastChoice = false
                                    finishArgument()
                                }
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            }
                            .padding(.bottom, 24)
                            .padding(.trailing, 36)
                        }
                    }
                    .padding(.horizontal, 36)
                }
            }
        }
    }

    private func argumentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("[ \(title) ]")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func applyReason(_ reason: ArgumentEvent.Reason, for claim: Claim) {
        let beforeSnapshot = refitPosterior ?? sessionRecord.finalPosterior

        if let w = reason.weight {
            // Refit posterior with disputed decisions down-weighted
            let observations = sessionRecord.decisions.map { ($0.price, $0.trait, $0.engaged) }
            let weights = sessionRecord.decisions.map { d -> Double in
                claim.supportingDecisionIDs.contains(d.index) ? w : 1.0
            }

            let newPosterior = Posterior.from(observations: observations, weights: weights)
            let afterSnapshot = newPosterior.snapshot()
            self.refitPosterior = afterSnapshot

            let event = ArgumentEvent(
                claimID: claim.id,
                reason: reason,
                posteriorBefore: beforeSnapshot,
                posteriorAfter: afterSnapshot
            )
            argumentEvents.append(event)
        } else {
            // notMe holds dual hypotheses
            let event = ArgumentEvent(
                claimID: claim.id,
                reason: reason,
                posteriorBefore: beforeSnapshot,
                posteriorAfter: beforeSnapshot
            )
            argumentEvents.append(event)
        }

        withAnimation {
            self.activeReason = reason
        }
    }

    private func computeDualHypothesisMetrics() -> (fastRT: Double, slowRT: Double, nConsistent: Int) {
        let sorted = sessionRecord.decisions.sorted { $0.rtSeconds < $1.rtSeconds }
        let half = sorted.count / 2
        let fastSlice = sorted.prefix(half)
        let slowSlice = sorted.suffix(half)

        let fastRT = calculateMedian(fastSlice.map(\.rtSeconds)) ?? 1.2
        let slowRT = calculateMedian(slowSlice.map(\.rtSeconds)) ?? 3.8
        let nConsistent = fastSlice.count
        return (fastRT, slowRT, nConsistent)
    }

    private func calculateMedian(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        } else {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
    }

    private func finishArgument() {
        let finalSnapshot = refitPosterior ?? sessionRecord.finalPosterior
        let updatedRecord = SessionRecord(
            sessionID: sessionRecord.sessionID,
            startedAt: sessionRecord.startedAt,
            consentDwellMs: sessionRecord.consentDwellMs,
            consentReadDetails: sessionRecord.consentReadDetails,
            detailsDwellMs: sessionRecord.detailsDwellMs,
            selfImageLabel: sessionRecord.selfImageLabel,
            selfPredictedThetaE: sessionRecord.selfPredictedThetaE,
            eyeEnabled: sessionRecord.eyeEnabled,
            eyeTimestamp: sessionRecord.eyeTimestamp,
            eyeApproachMs: sessionRecord.eyeApproachMs,
            shadowAppearances: sessionRecord.shadowAppearances,
            shadowCorrect: sessionRecord.shadowCorrect,
            decisions: sessionRecord.decisions,
            movement: sessionRecord.movement,
            finalPosterior: finalSnapshot,
            argumentEvents: argumentEvents
        )
        onComplete(updatedRecord)
    }
}
