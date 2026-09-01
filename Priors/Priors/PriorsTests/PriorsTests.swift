//
//  PriorsTests.swift
//  PriorsTests
//
//

import Testing
import SpriteKit
import PriorsEngine
import CoreGraphics
import AVFoundation
@testable import Priors

struct PriorsTests {

    // MARK: - Tier 1 Tests

    @Test func engineIntegration() async throws {
        var p = Posterior()
        p.update(price: 0.3, trait: PriorsEngine.Trait.thetaE, engaged: true)
        let (mean, sd) = p.meanSD(.thetaE)
        #expect(Grids.cellCount == 12375)
        #expect(Scenarios.decisionCount == 30)
        #expect(mean > 0.0)
        #expect(sd > 0.0)
    }

    // MARK: - Tier 2 Tests

    @Test func consentLogTracking() async throws {
        let log = ConsentLog()
        #expect(log.consentDwellMs == 0)
        #expect(log.consentReadDetails == false)
        #expect(log.detailsDwellMs == nil)

        log.consentDwellMs = 1250
        log.consentReadDetails = true
        log.detailsDwellMs = 450

        #expect(log.consentDwellMs == 1250)
        #expect(log.consentReadDetails == true)
        #expect(log.detailsDwellMs == 450)
    }

    @Test func temperamentLabelMapping() async throws {
        #expect(SelfImageLabel.careful.rawValue == "Careful")
        #expect(SelfImageLabel.curious.rawValue == "Curious")
        #expect(SelfImageLabel.generous.rawValue == "Generous")
        #expect(SelfImageLabel.steady.rawValue == "Steady")

        #expect(SelfImageLabel.curious.claimedTrait == PriorsEngine.Trait.thetaE)
        #expect(SelfImageLabel.careful.claimedTrait == PriorsEngine.Trait.thetaE)
        #expect(SelfImageLabel.generous.claimedTrait == PriorsEngine.Trait.thetaI)
        #expect(SelfImageLabel.steady.claimedTrait == PriorsEngine.Trait.thetaI)
    }

    @Test func titleScreenDefault() async throws {
        let title = "The one who explored while it was free."
        let screen = TitleScreen(title: title)
        #expect(screen.title == title)
    }

    // MARK: - Tier 3 Tests

    @Test func paletteDecayStepMapping() async throws {
        let controller = PaletteController()
        #expect(controller.step(forMeanPosteriorSD: 0.30) == 0.0)
        #expect(controller.step(forMeanPosteriorSD: 0.20) == 1.0)
        #expect(controller.step(forMeanPosteriorSD: 0.15) == 2.0)
        #expect(controller.step(forMeanPosteriorSD: 0.10) == 3.0)
        #expect(controller.step(forMeanPosteriorSD: 0.06) == 4.0)
        #expect(controller.step(forMeanPosteriorSD: 0.00) == 5.0)

        // Continuous interpolation checks
        let midStep = controller.step(forMeanPosteriorSD: 0.175)
        #expect(midStep > 1.0 && midStep < 2.0)

        let p0 = controller.interpolatedParameters(forStep: 0.0)
        let p5 = controller.interpolatedParameters(forStep: 5.0)
        #expect(p0.saturation > p5.saturation)
        #expect(p0.brightness > p5.brightness)
    }

    @MainActor
    @Test func movementSamplerRecording() async throws {
        let sampler = MovementSampler()
        sampler.updatePosition(x: 100.0, y: 150.0)
        let s1 = sampler.recordSample()

        #expect(s1.x == 100.0)
        #expect(s1.y == 150.0)
        #expect(s1.moving == false)
        #expect(s1.regionID == "r_3_4") // 100/32 = 3, 150/32 = 4

        sampler.updatePosition(x: 110.0, y: 150.0)
        let s2 = sampler.recordSample()
        #expect(s2.moving == true)
        #expect(sampler.samples.count == 2)
    }

    // MARK: - Phase 3 (Village World & Gameplay Loop) Tests

    @MainActor
    @Test func villageMapBuilderDimensionsAndDeadSpace() async throws {
        let scene = SKScene(size: CGSize(width: 800, height: 600))
        let result = VillageMapBuilder.shared.buildVillage(in: scene)

        #expect(result.mapData.width == 80)
        #expect(result.mapData.height == 60)
        #expect(result.mapData.tileSize == 32.0)
        #expect(result.mapData.worldSize == CGSize(width: 2560, height: 1920))

        // SPEC §8: At least 30% of walkable area is empty dead space
        #expect(result.mapData.deadSpaceFraction >= 0.30)
        #expect(result.triggers.count == 30)
        #expect(result.eyeNode.name == "the_eye")

        // Check region lookup
        let regionCenter = VillageMapBuilder.shared.regionName(for: CGPoint(x: 40 * 32, y: 30 * 32))
        #expect(regionCenter == "r_village_square")
    }

    @MainActor
    @Test func villageAssetsAndCharacterNodes() async throws {
        let assets = VillageAssets.shared

        // Two frames per direction: Tiny Town ships one character pose, so the
        // walk is a derived two-frame bob (`scripts/build_assets.py`). The old
        // expectation of four came from slicing a four-direction cycle out of a
        // sheet that did not contain one — every "frame" was a different
        // standing character.
        for dir in Direction.allCases {
            let walkFrames = assets.playerWalkCycle(direction: dir)
            #expect(walkFrames.count == 2, "\(dir) walk cycle")
            for frame in walkFrames {
                #expect(frame.size().width > 0 && frame.size().height > 0)
            }
            let idleFrame = assets.playerIdleTexture(direction: dir)
            #expect(idleFrame.size().width > 0)
        }

        // Every tile type resolves, and resolves to a 16px source tile. This is
        // the guard on the index map: the previous atlas was sliced on a 32px
        // grid over 16px art, so `wallStone` rendered a window.
        for type in TileType.allCases {
            let tex = assets.texture(for: type)
            #expect(tex.size().width == 16, "\(type) is \(tex.size().width)px, expected 16")
            #expect(tex.size().height == 16, "\(type)")
        }

        // Left is right, mirrored — the pack has no separate left art.
        let facing = PlayerNode()
        facing.updateMovement(vector: CGVector(dx: -1, dy: 0))
        #expect(facing.xScale == -1)
        facing.updateMovement(vector: CGVector(dx: 1, dy: 0))
        #expect(facing.xScale == 1)

        let player = PlayerNode()
        #expect(player.currentDirection == .down)
        #expect(player.isMoving == false)

        player.updateMovement(vector: CGVector(dx: 1.0, dy: 0.0))
        #expect(player.currentDirection == .right)
        #expect(player.isMoving == true)

        player.updateMovement(vector: CGVector(dx: 0.0, dy: 0.0))
        #expect(player.isMoving == false)

        let shadow = ShadowNode()
        #expect(abs(shadow.alpha - 0.30) < 0.01) // SPEC §6.2: 30% alpha

        let eye = EyeNode()
        #expect(eye.children.count == 2) // SPEC §6.3: Two 2x2 white dots
    }

    @MainActor
    @Test func villageCoordinatorFull30DecisionLoop() async throws {
        let consent = ConsentLog()
        consent.consentDwellMs = 2400
        consent.consentReadDetails = true

        let coordinator = VillageCoordinator(
            consentLog: consent,
            selfImageLabel: .curious,
            eyeEnabled: true
        )

        #expect(coordinator.currentSlot == 0)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.lanternCount == 3)

        let scene = VillageScene(size: CGSize(width: 800, height: 600))
        let sampler = MovementSampler()

        var completedRecord: SessionRecord?
        coordinator.onSessionComplete = { record in
            completedRecord = record
        }

        // Run full 30-decision loop
        for slot in 0..<30 {
            coordinator.presentCurrentScenario(scene: scene)
            #expect(coordinator.isPresentingScenario == true)
            #expect(coordinator.activePrompt != nil)

            let prompt = coordinator.activePrompt!
            #expect(prompt.slot == slot)
            #expect(!prompt.title.isEmpty)

            let engaged = (slot % 2 == 0)
            coordinator.handleChoice(
                engaged: engaged,
                metrics: (approachFrac: 0.65, backtracks: 1, idleMs: 400),
                movementSampler: sampler,
                scene: scene
            )

            #expect(coordinator.isPresentingScenario == false)
            #expect(coordinator.currentSlot == slot + 1)
            #expect(coordinator.decisions.count == slot + 1)
        }

        #expect(coordinator.currentSlot == 30)
        #expect(completedRecord != nil)
        guard let record = completedRecord else { return }

        #expect(record.decisions.count == 30)
        #expect(record.selfImageLabel == .curious)
        #expect(record.consentDwellMs == 2400)
        #expect(record.finalPosterior.thetaEMean > 0)
        #expect(record.finalPosterior.thetaIMean > 0)

        // Check gaming metrics on the decisions
        let metrics = EventTriggers.gamingMetrics(decisions: record.decisions)
        #expect(metrics.rtRatio >= 0.0)
    }

    @Test func scenarioPromptFormatting() async throws {
        let post = Posterior()
        let state = SelectionState()

        for slot in 0..<6 {
            let design = ADOSelector.selectDesign(posterior: post, slot: slot, state: state)
            let prompt = ScenarioPromptData(design: design)
            #expect(!prompt.title.isEmpty)
            #expect(!prompt.bodyText.isEmpty)
            #expect(!prompt.engageButtonTitle.isEmpty)
            #expect(!prompt.declineButtonTitle.isEmpty)
        }
    }

    // MARK: - Phase 5 & 6 (The Reading & The Argument) Tests

    @Test func claimRendererCopyFormatting() async throws {
        let claim = Claim.make(
            id: "self_prediction_gap",
            kind: .selfPredictionGap,
            parameters: ["self_pred_pct": 70.0, "theta_e_pct": 42.0, "gap": 0.28],
            supportingDecisionIDs: [0, 1, 2],
            confidence: 0.04
        )!

        let rendered = try #require(ClaimRenderer.render(claim: claim))
        #expect(rendered.contains("Before this, I asked where your line was."))
        #expect(rendered.contains("You said 70%."))
        #expect(rendered.contains("It is 42%."))
    }

    @Test func argumentPosteriorRefitUncertaintyWidening() async throws {
        // Build observations from 10 decisions
        var obs: [(price: Double, trait: PriorsEngine.Trait, engaged: Bool)] = []
        for i in 0..<10 {
            obs.append((price: Double(i) * 0.08 + 0.1, trait: PriorsEngine.Trait.thetaE, engaged: i < 5))
        }

        // Full weight posterior
        let fullPosterior = Posterior.from(observations: obs)
        let (_, sdFull) = fullPosterior.meanSD(.thetaE)

        // Down-weighted posterior (disputed decision #4 down-weighted to 0.2)
        var weights = [Double](repeating: 1.0, count: 10)
        weights[4] = 0.2
        let downweightedPosterior = Posterior.from(observations: obs, weights: weights)
        let (_, sdDownweighted) = downweightedPosterior.meanSD(.thetaE)

        // Refit with down-weighting must widen the uncertainty band (higher SD)
        #expect(sdDownweighted >= sdFull - 0.001)
    }

    @Test func sessionClaimsOrderingAndHardestClaim() async throws {
        var post = Posterior()
        for i in 0..<10 {
            post.update(price: Double(i) * 0.08 + 0.1, trait: PriorsEngine.Trait.thetaE, engaged: i < 6)
        }

        let dummyDecisions = (0..<30).map { i in
            DecisionRecord(
                index: i,
                template: .path,
                trait: PriorsEngine.Trait.thetaE,
                skin: "old orchard",
                price: 0.35,
                engaged: i % 2 == 0,
                tPresented: Double(i) * 10.0,
                tDecided: Double(i) * 10.0 + 1.2,
                rtMs: 1200,
                approachFrac: 0.8,
                backtracks: 1,
                idleMs: 500,
                eyeWindow: false,
                eyeSide: nil,
                posteriorMeanE: 0.45,
                posteriorSDE: 0.05,
                posteriorMeanI: 0.40,
                posteriorSDI: 0.06,
                predictedEngage: 0.60
            )
        }

        let record = SessionRecord(
            sessionID: UUID(),
            startedAt: Date(),
            consentDwellMs: 2500,
            consentReadDetails: true,
            detailsDwellMs: 800,
            selfImageLabel: .curious,
            selfPredictedThetaE: 0.75,
            eyeEnabled: false,
            eyeTimestamp: nil,
            eyeApproachMs: 0,
            shadowAppearances: [],
            shadowCorrect: [],
            decisions: dummyDecisions,
            movement: [],
            finalPosterior: post.snapshot(),
            argumentEvents: []
        )

        let claims = ClaimGenerator.generate(session: record)
        #expect(!claims.isEmpty)

        // Verify all claims render verbatim text
        for claim in claims {
            let text = try #require(ClaimRenderer.render(claim: claim))
            #expect(!text.isEmpty)
        }

        // Hardest claim is placed 3rd from last if count >= 3
        if claims.count >= 3 {
            let hardest = ClaimGenerator.hardest(claims)
            let thirdFromLast = claims[claims.count - 3]
            if let hardest {
                #expect(thirdFromLast.id == hardest.id)
            }
        }
    }

    // MARK: - Audio Decay Engine (SPEC §8.1 & NOTES-audio.md) Tests

    @Test func audioStemStepSchedule() async throws {
        #expect(AudioManager.step(forMeanPosteriorSD: 0.25) == 0) // > 0.20 -> Step 0 (Full mix)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.201) == 0)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.18) == 1) // 0.15-0.20 -> Step 1 (Bells dropped)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.151) == 1)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.12) == 2) // 0.10-0.15 -> Step 2 (Perc dropped)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.101) == 2)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.08) == 3) // 0.06-0.10 -> Step 3 (Melody dropped)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.06) == 3)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.059) == 4) // < 0.06 -> Step 4 (Bass dropped, Pad only)
        #expect(AudioManager.step(forMeanPosteriorSD: 0.01) == 4)
    }

    @Test func audioActiveStemsPerStep() async throws {
        // Step 0: All 5 active
        let s0 = AudioManager.activeStems(forStep: 0)
        #expect(s0 == Set(AudioStem.allCases))
        #expect(s0.count == 5)

        // Step 1: Bells dropped
        let s1 = AudioManager.activeStems(forStep: 1)
        #expect(!s1.contains(.bells))
        #expect(s1 == [.perc, .melody, .bass, .pad])

        // Step 2: Perc dropped
        let s2 = AudioManager.activeStems(forStep: 2)
        #expect(!s2.contains(.bells) && !s2.contains(.perc))
        #expect(s2 == [.melody, .bass, .pad])

        // Step 3: Melody dropped
        let s3 = AudioManager.activeStems(forStep: 3)
        #expect(s3 == [.bass, .pad])

        // Step 4: Bass dropped (Pad only)
        let s4 = AudioManager.activeStems(forStep: 4)
        #expect(s4 == [.pad])

        // Step 5: Pad dropped (Pure room tone / silence)
        let s5 = AudioManager.activeStems(forStep: 5)
        #expect(s5.isEmpty)
    }

    @Test func audioFadeEqualPowerCosineCurve() async throws {
        // At progress 0.0: volume is 1.0 (cos(0) = 1.0)
        let v0 = AudioManager.fadeVolume(progress: 0.0)
        #expect(abs(v0 - 1.0) < 0.001)

        // At progress 0.5: volume is cos(pi/4) = 1/sqrt(2) ≈ 0.7071
        let vMid = AudioManager.fadeVolume(progress: 0.5)
        #expect(abs(vMid - Float(cos(Double.pi * 0.25))) < 0.001)

        // At progress 1.0: volume is 0.0 (cos(pi/2) = 0.0)
        let v1 = AudioManager.fadeVolume(progress: 1.0)
        #expect(abs(v1 - 0.0) < 0.001)

        // Clamping checks
        #expect(AudioManager.fadeVolume(progress: -0.5) == 1.0)
        #expect(AudioManager.fadeVolume(progress: 1.5) == 0.0)
    }

    @Test func audioMonotonicOneWayDecay() async throws {
        let audioManager = AudioManager()
        #expect(audioManager.highestStepReached == 0)
        #expect(audioManager.mutedStems.isEmpty)

        // Step 1: SD = 0.18 -> mutes bells
        audioManager.updateDecay(meanPosteriorSD: 0.18)
        #expect(audioManager.highestStepReached == 1)
        #expect(audioManager.mutedStems.contains(.bells))

        // Step 3: SD = 0.08 -> mutes perc and melody
        audioManager.updateDecay(meanPosteriorSD: 0.08)
        #expect(audioManager.highestStepReached == 3)
        #expect(audioManager.mutedStems.contains(.bells))
        #expect(audioManager.mutedStems.contains(.perc))
        #expect(audioManager.mutedStems.contains(.melody))

        // Fluctuating SD increase (e.g. 0.25) must NEVER un-mute layers
        audioManager.updateDecay(meanPosteriorSD: 0.25)
        #expect(audioManager.highestStepReached == 3)
        #expect(audioManager.mutedStems.contains(.bells))
        #expect(audioManager.mutedStems.contains(.perc))
        #expect(audioManager.mutedStems.contains(.melody))

        // Transition to The Reading (Step 5)
        audioManager.enterReadingRoomTone()
        #expect(audioManager.highestStepReached == 5)
        #expect(audioManager.mutedStems.contains(.pad))
    }

    @Test func audioProceduralStemSynthesis() async throws {
        let audioManager = AudioManager()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioManager.sampleRate,
            channels: AudioManager.channelCount,
            interleaved: false
        ) else {
            #expect(Bool(false), "Failed to construct AVAudioFormat")
            return
        }

        #expect(AudioManager.loopSampleCount == 2_194_286)
        #expect(AudioManager.fadeDurationSeconds == 2.5)

        for stem in AudioStem.allCases {
            let buffer = audioManager.generateProceduralStem(stem: stem, format: format)
            #expect(buffer.frameLength == AudioManager.loopSampleCount)
            #expect(buffer.format.channelCount == 2)
            #expect(buffer.format.sampleRate == 48000.0)

            guard let left = buffer.floatChannelData?[0],
                  let right = buffer.floatChannelData?[1] else {
                #expect(Bool(false), "Channel data unavailable for stem \(stem)")
                continue
            }

            // Verify non-zero audio energy in both stereo channels
            var maxL: Float = 0.0
            var maxR: Float = 0.0
            let strideCount = 500
            for i in stride(from: 0, to: Int(buffer.frameLength), by: strideCount) {
                maxL = max(maxL, abs(left[i]))
                maxR = max(maxR, abs(right[i]))
            }

            #expect(maxL > 0.001, "Stem \(stem) left channel has no energy")
            #expect(maxR > 0.001, "Stem \(stem) right channel has no energy")
        }
    }

    // MARK: - COPY.md verbatim rendering (SPEC §2.1, §9.1; COPY "final wording")
    //
    // COPY.md: "This is final wording. Do not rewrite, do not 'improve'."
    // These assert the rendered string equals its COPY section character for
    // character, including line breaks. A renderer that drops a line or
    // substitutes its own sentence fails here.

    @Test func copyR1OpeningIsVerbatim() async throws {
        let claim = Claim.make(
            id: "opening", kind: .opening,
            parameters: ["n_decisions": 30],
            supportingDecisionIDs: [0], confidence: 0
        )!
        #expect(ClaimRenderer.render(claim: claim) == """
        You made 30 decisions.
        I recorded 30.
        """)
    }

    @Test func copyR2ConfirmLowPriceKeepsItsSecondLine() async throws {
        let claim = Claim.make(
            id: "explore_below_line", kind: .confirmLowPrice,
            parameters: ["low_price_pct": 42, "n_low_explored": 7, "n_low_offered": 8],
            supportingDecisionIDs: [0], confidence: 0.05
        )!
        #expect(ClaimRenderer.render(claim: claim) == """
        You explored every path below 42% risk.
        7 of 8.
        """)
    }

    @Test func copyR3ConfirmQuickKeepsItsSecondLine() async throws {
        let claim = Claim.make(
            id: "quick_when_cheap", kind: .confirmQuick,
            parameters: ["median_rt_low": 1.24],
            supportingDecisionIDs: [0], confidence: 0.05
        )!
        #expect(ClaimRenderer.render(claim: claim) == """
        You were quick about it. Median 1.2 seconds.
        You did not deliberate when it was cheap.
        """)
    }

    // MARK: - No fabricated report content (SPEC §2.1, §9.1)
    //
    // COPY's forbidden list ends with "Any number the log does not contain".
    // A renderer that substitutes a plausible default for a missing parameter
    // prints an invented number or an invented place as if it were measured.
    // The contract is: render every value, or render nothing.

    /// Every claim kind, populated with exactly the values its COPY section
    /// interpolates. Used to prove the renderer accepts complete claims.
    private static func completeClaim(for kind: ClaimKind) -> Claim {
        let numbers: [String: Double]
        let strings: [String: String]
        switch kind {
        case .opening:
            numbers = ["n_decisions": 30]; strings = [:]
        case .confirmLowPrice:
            numbers = ["low_price_pct": 42, "n_low_explored": 7, "n_low_offered": 8]; strings = [:]
        case .confirmQuick:
            numbers = ["median_rt_low": 1.2]; strings = [:]
        case .theLine:
            numbers = ["high_price_pct": 42, "n_high_explored": 2,
                       "n_high_offered": 9, "theta_e_pct": 42]; strings = [:]
        case .selfPredictionGap:
            numbers = ["self_pred_pct": 70, "theta_e_pct": 42]; strings = [:]
        case .nearMiss:
            numbers = ["ordinal": 7, "approach_pct": 80, "idle_seconds": 2.4]; strings = [:]
        case .pointlessDetail:
            numbers = ["revisit_count": 5]; strings = ["landmark": "r_northwest_woods"]
        case .moralLine:
            numbers = ["error_time": 428, "error_cost_pct": 30, "theta_i_pct": 31]
            strings = ["error_skin": "villager thanks you for another's work",
                       "error_choice": "kept walking"]
        case .temperament:
            numbers = ["measured_pct": 42]; strings = ["self_image_label": "Curious"]
        case .repeatDivergence:
            numbers = ["a_ordinal": 3, "b_ordinal": 11]; strings = [:]
        case .eyeComparison:
            numbers = ["eye_time": 512, "gave_before": 3, "gave_after": 1]; strings = [:]
        case .eyeApproach:
            numbers = ["eye_approach_seconds": 6.0]; strings = [:]
        case .consentNumber:
            numbers = ["consent_seconds": 2.4]; strings = [:]
        case .gamingBreak:
            numbers = ["fit_break": 22, "rt_before": 1.2, "rt_after": 3.4]; strings = [:]
        case .gamingUnknown:
            numbers = ["fit_break": 22]; strings = [:]
        }
        return Claim(id: "fixture_\(kind.rawValue)", kind: kind,
                     parameters: numbers, stringParameters: strings,
                     supportingDecisionIDs: [0], confidence: 0.05)
    }

    @Test func everyClaimKindRendersWhenItsParametersArePresent() async throws {
        for kind in ClaimKind.allCases {
            let text = ClaimRenderer.render(claim: Self.completeClaim(for: kind))
            #expect(text != nil, "\(kind) has every parameter but did not render")
            #expect(text?.isEmpty == false, "\(kind) rendered an empty string")
        }
    }

    @Test func noClaimKindRendersWithoutItsParameters() async throws {
        for kind in ClaimKind.allCases {
            let bare = Claim(id: "bare_\(kind.rawValue)", kind: kind,
                             parameters: [:], stringParameters: [:],
                             supportingDecisionIDs: [0], confidence: 0.05)
            #expect(ClaimRenderer.render(claim: bare) == nil,
                    "\(kind) invented content for a claim carrying no parameters")
        }
    }

    @Test func droppingAnySingleParameterStopsTheClaimRendering() async throws {
        for kind in ClaimKind.allCases {
            let complete = Self.completeClaim(for: kind)
            for key in complete.parameters.keys {
                var reduced = complete.parameters
                reduced.removeValue(forKey: key)
                let claim = Claim(id: complete.id, kind: kind,
                                  parameters: reduced,
                                  stringParameters: complete.stringParameters,
                                  supportingDecisionIDs: [0], confidence: 0.05)
                #expect(ClaimRenderer.render(claim: claim) == nil,
                        "\(kind) still rendered after '\(key)' was removed")
            }
            for key in complete.stringParameters.keys {
                var reduced = complete.stringParameters
                reduced.removeValue(forKey: key)
                let claim = Claim(id: complete.id, kind: kind,
                                  parameters: complete.parameters,
                                  stringParameters: reduced,
                                  supportingDecisionIDs: [0], confidence: 0.05)
                #expect(ClaimRenderer.render(claim: claim) == nil,
                        "\(kind) still rendered after string '\(key)' was removed")
            }
        }
    }

    /// COPY R7 asserts "There is nothing at {landmark}". An unnamed grid cell
    /// has no landmark to name, so the claim must not render rather than
    /// inventing a place the village does not contain.
    @Test func pointlessDetailDoesNotInventAPlaceForAnUnnamedRegion() async throws {
        let claim = Claim(id: "pointless_detail", kind: .pointlessDetail,
                          parameters: ["revisit_count": 5],
                          stringParameters: ["landmark": "r_18_29"],
                          supportingDecisionIDs: [0], confidence: 0.05)
        #expect(ClaimRenderer.render(claim: claim) == nil)
    }

    @Test func temperamentDoesNotRenderAnUnrecognisedLabel() async throws {
        let claim = Claim(id: "temperament", kind: .temperament,
                          parameters: ["measured_pct": 42],
                          stringParameters: ["self_image_label": "Reckless"],
                          supportingDecisionIDs: [0], confidence: 0.05)
        #expect(ClaimRenderer.render(claim: claim) == nil)
    }

    /// A claim that cannot render must not silently become a blank screen with
    /// no tap target — the reading has no skip, so that would strand the player.
    @Test func readingScreenSkipsClaimsThatCannotRender() async throws {
        let renderable = Self.completeClaim(for: .opening)
        let unrenderable = Claim(id: "bare", kind: .theLine,
                                 parameters: [:], stringParameters: [:],
                                 supportingDecisionIDs: [0], confidence: 0.05)
        let pages = ReadingScreen.pages(for: [renderable, unrenderable])
        #expect(pages.count == 1)
        #expect(pages.first?.claim.id == renderable.id)
    }

    // MARK: - COPY v1.1 R9 / R10

    /// COPY R9 selects `{error_description}` from the logged skin — the surface
    /// the player actually saw — and the result must read as a verb phrase after
    /// "you ", not as the bare noun phrase the skin is.
    @Test func copyR9DescribesTheLoggedSkinAsSomethingTheyDid() async throws {
        let claim = Claim(
            id: "moral_line", kind: .moralLine,
            parameters: ["error_time": 428, "error_cost_pct": 30, "theta_i_pct": 31],
            stringParameters: ["error_skin": "villager thanks you for another's work",
                               "error_choice": "kept walking"],
            supportingDecisionIDs: [4], confidence: 0.05)
        #expect(ClaimRenderer.render(claim: claim) == """
        At 7:08 you were thanked for another's work.
        Nothing here would have known. It cost 30%.

        You kept walking.

        Your line is somewhere near 31%.
        """)
    }

    @Test func copyR9RendersEveryAuthoredSkin() async throws {
        let expected = [
            "wrong house": "delivered to the wrong house",
            "dropped lantern": "dropped a lantern and left it",
            "villager thanks you for another's work": "were thanked for another's work",
        ]
        for (skin, phrase) in expected {
            let claim = Claim(
                id: "moral_line", kind: .moralLine,
                parameters: ["error_time": 60, "error_cost_pct": 10, "theta_i_pct": 20],
                stringParameters: ["error_skin": skin, "error_choice": "went back"],
                supportingDecisionIDs: [1], confidence: 0.05)
            let text = try #require(ClaimRenderer.render(claim: claim),
                                    "authored skin '\(skin)' did not render")
            #expect(text.hasPrefix("At 1:00 you \(phrase)."))
        }
    }

    /// A skin with no row in COPY's table has no authored phrase, so R9 must not
    /// render rather than print the raw skin as if it were a sentence.
    @Test func copyR9DoesNotRenderASkinCopyDoesNotName() async throws {
        let claim = Claim(
            id: "moral_line", kind: .moralLine,
            parameters: ["error_time": 428, "error_cost_pct": 30, "theta_i_pct": 31],
            stringParameters: ["error_skin": "villager needs your lantern",
                               "error_choice": "kept walking"],
            supportingDecisionIDs: [4], confidence: 0.05)
        #expect(ClaimRenderer.render(claim: claim) == nil)
    }

    @Test func copyR10RendersTheSentenceForTheClaimedTrait() async throws {
        func line(_ label: String, _ pct: Double) throws -> String {
            let claim = Claim(id: "temperament", kind: .temperament,
                              parameters: ["measured_pct": pct],
                              stringParameters: ["self_image_label": label],
                              supportingDecisionIDs: [0], confidence: 0.05)
            return try #require(ClaimRenderer.render(claim: claim))
        }
        #expect(try line("Careful", 42) == """
        You chose Careful.

        Your line for exploring an unlit path measured at 42%.
        """)
        #expect(try line("Steady", 31) == """
        You chose Steady.

        Your line for bearing a cost no one would have seen measured at 31%.
        """)
    }

    /// SPEC §8.1 — the decay has to be visible, and it only goes one way.
    ///
    /// The vignette previously ran 0.70 -> 0.95: the village opened at 70%
    /// darkness and the entire five-step schedule moved alpha by 0.25.
    @MainActor
    @Test func duskVignetteOpensClearAndDarkensMonotonically() async throws {
        let start = VillageScene.vignetteAlpha(forStep: 0)
        let end = VillageScene.vignetteAlpha(forStep: 5)
        #expect(start < 0.15, "the village opens at \(start) alpha; SPEC §1 calls it cheerful")
        #expect(end > 0.70, "fully decayed vignette is only \(end)")
        #expect(end < 1.0, "the player must still be able to see the path")
        #expect(end - start > 0.5, "the decay spans only \(end - start) of alpha")

        var previous = -1.0
        for tenth in 0...50 {
            let a = Double(VillageScene.vignetteAlpha(forStep: Double(tenth) / 10.0))
            #expect(a >= previous, "vignette went backwards at step \(Double(tenth) / 10.0)")
            previous = a
        }
        // Clamped outside the schedule.
        #expect(VillageScene.vignetteAlpha(forStep: -3) == start)
        #expect(VillageScene.vignetteAlpha(forStep: 99) == end)
    }

    /// The temperament tap froze because switching to the village built the
    /// whole 80x60 map as individual nodes on the main thread: ~4,800 ground
    /// sprites, ~560 perimeter physics bodies and ~63 more for the pond.
    ///
    /// Ground is now two `SKTileMapNode`s and the boundaries are area
    /// rectangles. This pins the structure rather than a wall-clock time, which
    /// would be flaky in a debug build — but it is the thing that caused the
    /// stall, so it is the thing worth guarding.
    @MainActor
    @Test func villageBuildsWithoutANodePerTile() async throws {
        let root = SKNode()
        _ = VillageMapBuilder.shared.buildVillage(in: root)

        func count(_ node: SKNode) -> Int {
            1 + node.children.reduce(0) { $0 + count($1) }
        }
        func bodies(_ node: SKNode) -> Int {
            (node.physicsBody == nil ? 0 : 1) + node.children.reduce(0) { $0 + bodies($1) }
        }

        let total = count(root)
        let physics = bodies(root)
        let tileMaps = root.children.compactMap { $0 as? SKTileMapNode }

        #expect(tileMaps.count == 2, "ground and canopy should each be one tile map")
        #expect(total < 1_000, "village built \(total) nodes; the per-tile version made ~5,500")
        #expect(physics < 120, "village made \(physics) physics bodies; the per-tile version made ~630")

        // Still a full-size map with the tiles actually set.
        for map in tileMaps {
            #expect(map.numberOfColumns == 80)
            #expect(map.numberOfRows == 60)
        }
    }
}
