# Priors — Handover Document

## 1. Project Status & State

| Component | Status | Verification / Notes |
|---|---|---|
| `priors-research/` (Python) | **Complete** | 165 unit tests passing. Do not modify. |
| `PriorsEngine/` (Swift Package) | **Complete** | 57 unit tests passing. Do not modify. |
| `Priors/` (iOS App) | **Tiers 1–4 Complete** | All unit tests passing on iPhone 17 Simulator (iOS 26.5). |
| `SPEC.md` / `Info.plist` / `project.pbxproj` | **Updated to Landscape** | Landscape mode configured per user direction; HIG safe areas & touch targets implemented. |

---

## 2. What Was Accomplished in the Previous Session

1. **Tier 1 (Prerequisites)**:
   - Wired `PriorsEngine` as a local Swift package dependency to the Xcode project.
   - Corrected `NOTES-foundation-models.md` confirming `FoundationModels` framework requires **iOS 26.0+** with exact enum cases (`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`).
2. **Tier 2 (Screens — `Priors/Priors/Screens/`)**:
   - `ConsentScreen.swift`: Exact verbatim copy, monotonic `ContinuousClock` timing for `consentDwellMs` and `detailsDwellMs`, `ConsentLog` tracking.
   - `TemperamentScreen.swift`: Captures `SelfImageLabel` (`.careful`, `.curious`, `.generous`, `.steady`) with decision elapsed time in ms.
   - `SelfPredictionScreen.swift`: 0–100% risk slider anchored at strictly 50% default.
   - `TitleScreen.swift`: Centered single line on black background.
3. **Tier 3 (Village Systems — `Priors/Priors/Village/`)**:
   - `PaletteController.swift`: Runtime continuous color transform (`CIFilter` / `SKEffectNode`) implementing `step(forMeanPosteriorSD:)` mapping posterior SD (0.25 -> 0.00) to steps 0.0 -> 5.0 (warm amber -> room tone).
   - `VirtualControls.swift`: Landscape dual-thumb layout with bottom-left thumbstick (normalized clamped `CGVector`), bottom-right interact button, and lantern-count-only HUD.
   - `MovementSampler.swift`: 4 Hz background sampling loop emitting `[MovementSample]` with monotonic clock and region ID lookup.
4. **Tier 4 (Assets & Audio)**:
   - Acquired all CC0 asset packs into `Priors/Assets-source/` with `LICENSE` files alongside.
   - Authored `NOTES-audio.md` defining 5-layer stems (84 BPM, D Dorian / A Minor, 48 kHz 24-bit PCM, 2.5s fade removal schedule, GarageBand Apple Loops royalty-free verification).
5. **App Coordinator**:
   - `PriorsApp.swift` wired to manage the session phase state machine: `.consent` -> `.temperament` -> `.village` -> `.selfPrediction` -> `.title`.
6. **Visual Style Decision**:
   - Locked in **Option 1 ("Cozy Storybook Village")** using Daniel Cook / Lostgarden 32×32 tiles + Stephen Challener faceless character bases from `Priors/Assets-source/` for maximum psychological contrast (uncanny valley) against the Bayesian readout.

---

## 3. Immediate Mission for the Next Session

Build the **SpriteKit Village World & Gameplay Loop (Phase 3)**:

1. **Character Sprite Animations**:
   - Slice 32×32 4-direction walk cycles (Down, Up, Left, Right, 4 frames each) from `Priors/Assets-source/oga-character-bases/rpgbaseformatted.png` and assemble `SKAction` animations on the player sprite.
2. **Village Tilemap (80×60 Tiles)**:
   - Build the top-down village scene using Lostgarden/OGA 32×32 tiles (`Priors/Assets-source/oga-classic-rpg-tileset/`), ensuring $\ge 30\%$ dead space for exploration.
3. **Player Physics & Virtual Controls Integration**:
   - Drive player movement via the virtual thumbstick vector in `VirtualControlsView`, handle tile collisions, and feed coordinates into `MovementSampler` at 4 Hz.
4. **ADO Scenario Triggers (30 Decisions)**:
   - Author scenario trigger zones across the 6 templates (`PATH`, `DETOUR`, `ERROR`, `CREDIT`, `GIVE`, `TRADE`) with ADO price selection via `PriorsEngine.ADOSelector` and posterior updates via `PriorsEngine.Posterior`.
5. **Dusk Decay Hook**:
   - Connect `PaletteController` to the village scene's `SKEffectNode` so the scene shifts continuously from warm amber to cool grey-blue as posterior SD decreases.
6. **In-Village Events (`SPEC §6`)**:
   - Implement Falsification pricing (§6.1), Predictive shadow (§6.2), The eye (§6.3, once between decisions 14–20), and Gaming detection metrics (§6.4).
