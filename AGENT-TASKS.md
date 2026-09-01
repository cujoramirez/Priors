# Priors — parallel agent task queue

For Antigravity agents working while the main session is paused. Work top to
bottom: Tier 1 unblocks everything else.

---

## READ THIS FIRST — non-negotiables

`SPEC.md` §2 lists eight rules. Violating any breaks the project. Several are
things an agent will otherwise "helpfully" add. **Never add, in any file:**

- a score, points, XP, stars, or any numeric reward
- a share button, leaderboard, or any comparison between players
- encouragement, congratulation, reassurance, or praise ("Nice!", "Well done")
- a confidence meter, prediction display, or progress bar during play
- a network call of any kind — no analytics, no crash reporting, no CloudKit,
  no telemetry, no remote config, no font CDN. `Nothing leaves the device` must
  be literally true
- a named protagonist, dialogue for the player character, or a fail state
- faces on villagers (SPEC §8 — faces invite role-play)
- any sentence containing "you are", "you're the type", or "your personality"

**All player-facing wording comes from `COPY.md` verbatim.** Do not write,
improve, paraphrase, or generate copy. If a screen needs text that is not in
`COPY.md`, leave a `// TODO: copy needed for X` comment and move on.

### File boundaries

| Path | Rule |
|---|---|
| `priors-research/` | **Do not touch.** Finished and verified. |
| `PriorsEngine/Sources/`, `PriorsEngine/Tests/` | **Do not touch.** Main session owns this. |
| `SPEC.md`, `SCHEMA.md`, `COPY.md` | **Do not edit.** Symlinked into all three repos — editing one edits all. Read freely. |
| `Priors/Priors/` | Yours. This is the app. |
| repo root `*.md` | Yours for notes. |

Commit nothing. Leave changes in the working tree.

---

# TIER 1 — do these first, they unblock everything

## T1.1 Wire PriorsEngine into the Xcode project

**Why first:** every other app task needs to import the engine.

Add `/Users/gading/Documents/Priors/PriorsEngine` as a **local Swift package
dependency** of the `Priors` target (Xcode: File → Add Package Dependencies →
Add Local). Then link the `PriorsEngine` library product to the app target.

Prove it works — add to `PriorsApp.swift` a temporary startup check:

```swift
import PriorsEngine

// TEMPORARY smoke check — delete once other engine code exists.
private func engineSmokeCheck() {
    var p = Posterior()
    p.update(price: 0.3, trait: .thetaE, engaged: true)
    let (mean, sd) = p.meanSD(.thetaE)
    print("PriorsEngine linked. theta_e mean=\(mean) sd=\(sd)")
    print("cells=\(Grids.cellCount), decisions=\(Scenarios.decisionCount)")
}
```

**Acceptance:** `xcodebuild -project Priors/Priors/Priors.xcodeproj -scheme Priors
-destination 'generic/platform=iOS Simulator' build` succeeds, and the printed
`cells=12375`, `decisions=30`.

**Note:** `Package.swift` declares `platforms: [.iOS(.v18), .macOS(.v15)]`. The
app targets iOS 26. That is fine — a package may support older platforms than
its consumer. Do not edit `Package.swift`.

## T1.2 Re-verify the Foundation Models version claim

`NOTES-foundation-models.md` currently says "iOS 18.1+ / iOS 26+". These are
probably two different things being merged:

- Apple Intelligence as a **feature** arrived in iOS 18.1
- the **Foundation Models framework** — `import FoundationModels`,
  `@Generable`, `@Guide`, `LanguageModelSession`, `SystemLanguageModel` — is
  iOS 26

SPEC §9.3 makes "iOS < 26" the fallback trigger, so getting this wrong changes
what we build. Confirm against Apple's official developer documentation, and
correct the note. State clearly, with a doc URL for each:

1. the minimum iOS version that has `import FoundationModels`
2. the minimum iOS version for `@Generable`
3. the exact enum cases of the unavailability reason type, spelled as Apple
   spells them
4. whether the simulator can run it at all, or whether a device is required

If a claim can't be confirmed from official docs, say "unverified" rather than
guessing. This note will be used to write real code.

---

# TIER 2 — the pre-village screens

These are the most mechanical work in the project: exact copy, exact logging,
no game logic. Each is one SwiftUI view plus a small state object.

Put them in `Priors/Priors/Priors/Screens/`. Use `PriorsEngine` types
(`SelfImageLabel`, etc.) rather than declaring new ones.

Shared requirements for all Tier 2 screens:
- portrait only, iPhone only
- copy **verbatim** from `COPY.md`, including line breaks
- no back button, no skip button, no progress indicator
- system font is fine for now; a pixel font comes later

## T2.1 Consent screen — SPEC §7.1, COPY "Consent screen"

Exact text, both panels, from `COPY.md`.

Log to an observable `ConsentLog`:
- `consentDwellMs` — milliseconds from screen appearing to `[ Start ]` tapped
- `consentReadDetails` — did they tap `[ What's collected ]`
- `detailsDwellMs` — milliseconds the details panel was open, nil if never opened

Use a monotonic clock (`ContinuousClock` or `CACurrentMediaTime()`), **not**
`Date()` — wall clock can jump.

**This number is the point of the screen.** SPEC §2.6: the consent screen was
built to be tapped through, and the report says so. Do not add anything that
encourages reading it — no highlight, no delay before Start becomes tappable,
no "please read". Measure, don't nudge.

**Acceptance:** tapping straight through logs a dwell under 2000ms; opening
details and closing logs `consentReadDetails == true` and a plausible
`detailsDwellMs`.

## T2.2 Temperament screen — SPEC §7.2, COPY "Temperament"

Four options: Careful / Curious / Generous / Steady. Framed as character
creation. Maps to `PriorsEngine.SelfImageLabel`.

Log `selfImageLabel`. Also log time-to-choose in ms (useful later, harmless now).

No "are you sure", no preview of what each means, no descriptions. The four
words are the whole screen.

## T2.3 Self-prediction slider — SPEC §7.3, COPY "Self-prediction"

Slider 0–100%. Log `selfPredictedThetaE` as 0.0–1.0 (divide by 100).

Starting position must be **50%**, not 0 and not a remembered value — a biased
default corrupts the headline claim in COPY R5.

No live numeric readout of the posterior, no hint about what was measured.

## T2.4 Title screen — SPEC §11

One line, centred. Nothing else on the screen. No menu, no list of other
titles, no share button, no replay button.

For now render a placeholder passed in as a `String`. The real line comes from
`ClaimGenerator.titleClaim`.

---

# TIER 3 — isolated village systems

Each is self-contained and testable without the village existing.

Put these in `Priors/Priors/Priors/Village/`.

## T3.1 Palette decay — SPEC §8, §8.1

**The important constraint:** SPEC §8 says dusk is a *continuous* palette shift,
and §8.1 defines five discrete decay steps. Continuous cannot be pre-baked, so
this must be a **runtime colour transform**, not six sets of sprites.

Build a `PaletteController` that:
- takes a `paletteStep: Double` (0.0–5.0, continuously interpolable)
- applies it to a SpriteKit scene via an `SKEffectNode` + `CIFilter`, or a
  fragment shader doing a palette lookup
- interpolates smoothly between steps rather than snapping

Palette anchors from SPEC §8.1: step 0 warm amber → step 3 cool → step 4
grey-blue → step 5 (reading). Pick plausible hex values and put them in one
clearly-marked table so they can be swapped later.

Expose `func step(forMeanPosteriorSD sd: Double) -> Double` implementing the
§8.1 table. `PosteriorSnapshot.meanSD` already exists in the engine.

**Acceptance:** a demo view with a slider driving `paletteStep` 0→5 shows a
smooth warm→cold transition with no visible snapping.

## T3.2 Virtual thumbstick + interact button — SPEC §8

- thumbstick bottom-left, interact button bottom-right
- thumbstick returns a normalised `CGVector` (magnitude 0–1)
- must handle: touch down outside the stick's rest position, drag beyond the
  ring (clamp, don't jump), multi-touch, and touch-up-outside
- no haptics, no sound, no visual "juice" on press

HUD carries **lantern count only**. No timer, no minimap, no objective marker.

## T3.3 Movement sampler — SCHEMA §2

Sample at **4 Hz** during the village phase, emitting
`PriorsEngine.MovementSample` (`t`, `x`, `y`, `moving`, `regionID`).

- `t` is seconds since session start, monotonic clock
- `moving` is whether the player moved since the previous sample
- `regionID` comes from a region lookup — stub it as a grid-cell name like
  `"r_12_34"` until real regions exist

At 4 Hz over ~13 minutes that is ~3100 samples per session. Keep it a flat
array of structs; do not log per-frame.

SCHEMA §2 says "Cheap. Log wide, interpret narrow." Do not filter, downsample,
or discard samples at collection time.

---

# TIER 4 — assets, no code

## T4.1 Acquire the chosen CC0 packs

From your own `ASSETS.md`, download the packs you rated CC0 into
`Priors/Assets-source/<pack-name>/`, each with its `LICENSE` file alongside.

Do not import into `Assets.xcassets` yet and do not modify any art. This is
acquisition only, so the main session can review before anything is committed
to a visual direction.

Update `ASSETS.md` with what was actually downloaded and the real file paths.

## T4.2 Audio stem specification — SPEC §8.1

Do **not** produce audio. Write `NOTES-audio.md` specifying it.

SPEC §8.1 needs five layers — melody, bells, pad, bass, perc — that are
removed one at a time as posterior SD falls, and **never added back**, with
**no change of key or tempo** at any point.

Specify:
- a single key and tempo for all five
- what each layer does musically, and that each must be loopable and
  seamless alone and in every subset used by the §8.1 table
- the removal order from §8.1 (bells → perc → melody → bass, leaving pad)
- format: which sample rate, which file format, loop-point handling in
  `AVAudioEngine` / `AVAudioPlayerNode`
- how a layer is removed — a fade over N ms, never a hard cut — and state
  the N you recommend
- confirm that GarageBand's Apple Loops are royalty-free for this use, with a
  source, since that is the intended production path

---

## When you finish a task

Append to `AGENT-LOG.md` at the repo root, one entry per task:

```
## <task id> — <title>
Status: done | partial | blocked
Files touched:
  - path (created | modified | deleted)
What was verified: <the actual command run and its result>
Assumptions made: <anything not specified that you chose>
Open questions for the main session: <or "none">
```

Be honest about `partial` and `blocked`. A task reported done that isn't is
worse than one reported blocked — the main session will build on top of it.
