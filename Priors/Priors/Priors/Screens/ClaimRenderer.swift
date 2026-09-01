//
//  ClaimRenderer.swift
//  Priors
//
//  Renders Claim objects into verbatim copy strings per COPY.md and SPEC §9.3.
//
//  Two rules govern this file:
//
//  1. COPY.md is final wording. Every case below reproduces its COPY section
//     character for character, including line breaks. Nothing is paraphrased,
//     shortened, or "improved".
//  2. SPEC §2.1 — "Nothing in the report is fictional." There are no default
//     values here. A claim missing a value its section interpolates does not
//     render at all; it returns nil and the caller drops the page. A plausible
//     default would print an invented number as if it had been measured, which
//     is exactly the failure COPY's forbidden list ends on: "Any number the log
//     does not contain."
//
//  `ClaimGenerator` already declines to build a claim it cannot support, so a
//  nil here means the generator and this renderer disagree about which values a
//  section needs — a bug to fix, not a gap to fill.
//

import Foundation
import PriorsEngine

public enum ClaimRenderer {

    /// Render a Claim into its exact verbatim multi-paragraph copy, or `nil`
    /// when the claim does not carry every value its COPY section interpolates.
    public static func render(claim: Claim) -> String? {
        let p = claim.parameters
        let sp = claim.stringParameters

        switch claim.kind {
        case .opening:
            guard let n = p["n_decisions"] else { return nil }
            return """
            You made \(int(n)) decisions.
            I recorded \(int(n)).
            """

        case .confirmLowPrice:
            guard let cut = p["low_price_pct"],
                  let explored = p["n_low_explored"],
                  let offered = p["n_low_offered"] else { return nil }
            return """
            You explored every path below \(int(cut))% risk.
            \(int(explored)) of \(int(offered)).
            """

        case .confirmQuick:
            guard let rt = p["median_rt_low"] else { return nil }
            return """
            You were quick about it. Median \(oneDecimal(rt)) seconds.
            You did not deliberate when it was cheap.
            """

        case .theLine:
            guard let cut = p["high_price_pct"],
                  let explored = p["n_high_explored"],
                  let offered = p["n_high_offered"],
                  let line = p["theta_e_pct"] else { return nil }
            return """
            Above \(int(cut))%, you explored \(int(explored)) in \(int(offered)).

            Your line is at \(int(line))%.
            """

        case .selfPredictionGap:
            guard let selfPred = p["self_pred_pct"],
                  let measured = p["theta_e_pct"] else { return nil }
            return """
            Before this, I asked where your line was.

            You said \(int(selfPred))%.
            It is \(int(measured))%.
            """

        case .nearMiss:
            guard let ordinalValue = p["ordinal"],
                  let approach = p["approach_pct"],
                  let idle = p["idle_seconds"],
                  let ord = ordinalString(int(ordinalValue)) else { return nil }
            return """
            At the \(ord) path you walked \(int(approach))% of the way in.
            You stood there for \(oneDecimal(idle)) seconds.
            Then you came back.

            You almost did it. I recorded that too.
            """

        case .pointlessDetail:
            guard let count = p["revisit_count"],
                  let region = sp["landmark"],
                  let landmark = landmarkName(region) else { return nil }
            return """
            You walked past \(landmark) \(int(count)) times.
            There is nothing at \(landmark).
            """

        case .moralLine:
            guard let time = p["error_time"],
                  let cost = p["error_cost_pct"],
                  let line = p["theta_i_pct"],
                  let skin = sp["error_skin"],
                  let desc = errorDescription(forSkin: skin),
                  let choice = sp["error_choice"] else { return nil }
            return """
            At \(formatTime(seconds: time)) you \(desc).
            Nothing here would have known. It cost \(int(cost))%.

            You \(choice).

            Your line is somewhere near \(int(line))%.
            """

        case .temperament:
            guard let label = sp["self_image_label"],
                  let measured = p["measured_pct"],
                  let traitSentence = measuredTraitSentence(label: label,
                                                            measuredPct: int(measured))
            else { return nil }
            return """
            You chose \(label).

            \(traitSentence)
            """

        case .repeatDivergence:
            guard let a = p["a_ordinal"], let b = p["b_ordinal"],
                  let aOrd = ordinalString(int(a)),
                  let bOrd = ordinalString(int(b)) else { return nil }
            return """
            The \(aOrd) path and the \(bOrd) path were the same price.

            You went in once.
            """

        case .eyeComparison:
            guard let time = p["eye_time"],
                  let before = p["gave_before"],
                  let after = p["gave_after"] else { return nil }
            return """
            At \(formatTime(seconds: time)) something watched you for three seconds.

            In the four minutes before, you gave away \(int(before)).
            In the four minutes after, you gave away \(int(after)).

            It was two white dots. Nothing was recording differently.

            You changed anyway.
            """

        case .eyeApproach:
            guard let seconds = p["eye_approach_seconds"] else { return nil }
            return """
            You walked to the doorway where it was and stood there
            for \(oneDecimal(seconds)) seconds.

            There was nothing there.

            I don't have a name for that. I only have the seconds.
            """

        case .consentNumber:
            guard let seconds = p["consent_seconds"] else { return nil }
            return """
            You spent \(oneDecimal(seconds)) seconds on the screen
            that told you I do this.

            So did almost everyone. It was built to be tapped through.

            I'm not going to pretend that was your fault alone.
            """

        case .gamingBreak:
            guard let brk = p["fit_break"],
                  let before = p["rt_before"],
                  let after = p["rt_after"] else { return nil }
            return """
            At decision \(int(brk)), something changed.

            Your choices stopped tracking price.
            Your response time went from \(oneDecimal(before)) seconds to \(oneDecimal(after)).
            """

        case .gamingUnknown:
            guard let brk = p["fit_break"] else { return nil }
            return """
            Deciding is faster than performing.

            I don't know what you chose after decision \(int(brk)).
            I know you weren't choosing the way you had been.
            """
        }
    }

    // MARK: - Formatting
    //
    // Formatting only changes how a measured value is written, never what it is.

    private static func int(_ v: Double) -> Int { Int(v) }

    private static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    private static func formatTime(seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// COPY R6 and R11 read "the {ordinal} path". The session is 30 decisions
    /// (SPEC §4), so anything outside 1...30 is not a decision index and the
    /// claim must not render rather than fall back to "31th".
    private static func ordinalString(_ n: Int) -> String? {
        let words = [
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
            "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth",
            "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
            "nineteenth", "twentieth", "twenty-first", "twenty-second",
            "twenty-third", "twenty-fourth", "twenty-fifth", "twenty-sixth",
            "twenty-seventh", "twenty-eighth", "twenty-ninth", "thirtieth",
        ]
        guard n >= 1, n <= words.count else { return nil }
        return words[n - 1]
    }

    /// COPY R9 — "At {error_time} you {error_description}."
    ///
    /// The log records which skin was shown (SCHEMA §1); COPY v1.1 fixes the
    /// phrase each skin is written as. The skin itself is a noun phrase and
    /// cannot follow "you", so interpolating it raw — as this file used to —
    /// produced a sentence with no verb.
    ///
    /// A skin with no row in COPY's table has no authored phrase, so R9 does not
    /// render. That is also what keeps `GIVE` out of this line: nothing here
    /// would have known is false when a villager asked and was refused.
    private static func errorDescription(forSkin skin: String) -> String? {
        switch skin {
        case "wrong house":
            return "delivered to the wrong house"
        case "dropped lantern":
            return "dropped a lantern and left it"
        case "villager thanks you for another's work":
            return "were thanked for another's work"
        default:
            return nil
        }
    }

    /// COPY R7 names a place: "There is nothing at {landmark}."
    ///
    /// The logged value is a region id (SCHEMA §2). The prose name is read out
    /// of the id's own words — it is a transliteration of the log, not a
    /// description added to it. `MovementSampler` also emits `r_<col>_<row>` for
    /// ground the map does not name; that patch has no landmark, so the claim
    /// does not render. Naming it anyway would put a place in the report that
    /// the village does not contain.
    private static func landmarkName(_ regionID: String) -> String? {
        let words = regionID
            .replacingOccurrences(of: "r_", with: "")
            .replacingOccurrences(of: "_", with: " ")
        if words.contains("cellar") { return "the cellar" }
        if words.contains("well") { return "the town well" }
        if words.contains("pond") { return "the pond" }
        if words.contains("hall") { return "the town hall" }
        if words.contains("woods") { return "the woods" }
        if words.contains("meadow") { return "the meadow" }
        if words.contains("square") { return "the village square" }
        return nil
    }

    /// COPY R10's second line is `{one_measured_sentence_about_that_trait}` —
    /// the section requires a sentence but does not fix its wording, so the four
    /// below are authored to fill it. Each states the measured value for the
    /// trait that temperament claims (`SelfImageLabel.claimedTrait`) and nothing
    /// more: no adjective of character, no "you are".
    ///
    /// An unrecognised label has no measured trait behind it, so no sentence is
    /// produced and the claim does not render.
    private static func measuredTraitSentence(label: String, measuredPct: Int) -> String? {
        switch label.lowercased() {
        case "curious":
            return "Your line for exploring an unlit path measured at \(measuredPct)%."
        case "careful":
            return "Your line for exploring an unlit path measured at \(measuredPct)%."
        case "generous":
            return "Your line for bearing a cost no one would have seen measured at \(measuredPct)%."
        case "steady":
            return "Your line for bearing a cost no one would have seen measured at \(measuredPct)%."
        default:
            return nil
        }
    }
}
