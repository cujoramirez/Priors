//
//  ScenarioDialogView.swift
//  Priors
//
//  Clean scenario dialog presentation matching SPEC §4, §4.2, and COPY voice rules.
//  No scores, no progress bars, no juice.
//

import SwiftUI
import PriorsEngine

public struct ScenarioPromptData: Sendable {
    public let slot: Int
    public let template: TemplateID
    public let skin: String
    public let price: Double
    public let title: String
    public let bodyText: String
    public let engageButtonTitle: String
    public let declineButtonTitle: String

    public init(design: Design) {
        self.slot = design.slot
        self.template = design.template
        self.skin = design.skin
        self.price = design.price

        let pricePct = Int(round(design.price * 100))

        switch design.template {
        case .path:
            self.title = design.skin.capitalized
            self.bodyText = "An unlit passage opens ahead.\nRisk of losing a lantern: \(pricePct)%."
            self.engageButtonTitle = "Enter"
            self.declineButtonTitle = "Stay on path"

        case .detour:
            self.title = design.skin.capitalized
            self.bodyText = "A blocked passage lies ahead.\nProbability of wasting time: \(pricePct)%."
            self.engageButtonTitle = "Take detour"
            self.declineButtonTitle = "Stay course"

        case .error:
            self.title = design.skin.capitalized
            self.bodyText = "You realise an error was made behind you.\nCost of going back: \(pricePct)%."
            self.engageButtonTitle = "Go back"
            self.declineButtonTitle = "Continue"

        case .credit:
            self.title = design.skin.capitalized
            self.bodyText = "A villager offers credit for work you did not do.\nSize of unearned gain: \(pricePct)%."
            self.engageButtonTitle = "Correct them"
            self.declineButtonTitle = "Accept silently"

        case .give:
            self.title = design.skin.capitalized
            self.bodyText = "A villager in the unlit lane asks for your lantern.\nCost of giving: \(pricePct)%."
            self.engageButtonTitle = "Give lantern"
            self.declineButtonTitle = "Keep lantern"

        case .trade:
            // SPEC §4.2: price is 1 - p_win
            let winPct = max(0, min(100, 100 - pricePct))
            self.title = design.skin.capitalized
            self.bodyText = "A trade is offered: keep 1 lantern, or gamble for 3.\nChance of winning 3: \(winPct)%."
            self.engageButtonTitle = "Take gamble"
            self.declineButtonTitle = "Keep 1 lantern"
        }
    }
}

public struct ScenarioDialogView: View {
    public let prompt: ScenarioPromptData
    public let onChoice: (Bool) -> Void

    public var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(prompt.title)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                Text(prompt.bodyText)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(white: 0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 16)

                HStack(spacing: 28) {
                    Button(action: {
                        onChoice(true)
                    }) {
                        Text(prompt.engageButtonTitle)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .frame(minWidth: 140, minHeight: 44)
                            .background(Color(white: 0.22))
                            .cornerRadius(4)
                    }
                    .accessibilityIdentifier("scenario_engage_button")

                    Button(action: {
                        onChoice(false)
                    }) {
                        Text(prompt.declineButtonTitle)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.75))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .frame(minWidth: 140, minHeight: 44)
                            .background(Color(white: 0.12))
                            .cornerRadius(4)
                    }
                    .accessibilityIdentifier("scenario_decline_button")
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(white: 0.25), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 520)
        }
    }
}
