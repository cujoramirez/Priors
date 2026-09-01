# Priors — Audio Stem Specification (SPEC §8.1)

This specification defines the interactive audio architecture for the village phase of **Priors**, implementing the progressive stem-removal schedule specified in `SPEC.md` §8.1.

---

## 1. Musical Composition Architecture

### 1.1 Master Tempo & Tonality
To ensure seamless multi-track synchronization and eliminate any psychoacoustic reset during gameplay:
- **Key**: **D Dorian** (or **A Minor** / **D Minor**) — contemplative, gentle folk tone that is neither overly triumphant nor dark.
- **Tempo**: **84.0 BPM** (fixed 4/4 meter).
- **Structure**: 16-bar loop cycle (64 beats = exactly 45.714 seconds at 84 BPM).
- **Rule**: **No change of key, tempo, or time signature at any point during gameplay.**

### 1.2 The Five Stems
All five stems are composed and rendered at the exact same start and end sample timestamps:

| Layer ID | Instrument / Sonic Role | Musical Function | Texture Quality |
| :--- | :--- | :--- | :--- |
| **`bells`** | Glockenspiel / Celesta / Music Box | Crystalline, cheerful top-end arpeggios on upbeat accents. | Carefree, whimsical, bright. |
| **`perc`** | Shaker, soft cajon, brushed wood clicks | Gentle walking pulse (quarter-note / eighth-note subdivision). | Movement, forward momentum. |
| **`melody`** | Acoustic nylon guitar / soft wooden flute | Playful 8-bar melodic question-and-answer theme. | Narrative warmth, curiosity. |
| **`bass`** | Upright acoustic / warm sub-pulse | Root and 5th grounding on beats 1 and 3. | Weight, spatial anchorage. |
| **`pad`** | Analogue string synth / bowed glass tone | Low-pass filtered sustained chords (Dm7 - G - Cmaj7 - Am). | Ambient harmony, constant dusk glow. |

### 1.3 Permutation & Harmony Rules
Every subset of layers defined by the §8.1 schedule must form a coherent, self-sufficient musical piece:
- **`[pad + bass + melody + perc + bells]`** (Full arrangement: cheerful, active village).
- **`[pad + bass + melody + perc]`** (Bells removed: subtly less whimsical).
- **`[pad + bass + melody]`** (Perc removed: organic, unhurried).
- **`[pad + bass]`** (Melody removed: contemplative, sparse, minimalist).
- **`[pad]`** (Bass removed: cold, static ambient drone before nightfall).
- **`[room tone]`** (Pad removed: absolute silence / gentle room resonance during the reading).

---

## 2. Progressive Stem Removal Schedule (SPEC §8.1)

Stems are muted one-way as posterior uncertainty ($\text{SD}_{\theta}$) drops. **Layers are never re-introduced.**

```
       Posterior SD           Active Layers              Removed Layer
       ────────────           ─────────────              ─────────────
Step 0 (> 0.20 SD)     Melody, Bells, Pad, Bass, Perc    None (Full mix)
Step 1 (0.15–0.20 SD)  Melody, Pad, Bass, Perc           Bells dropped
Step 2 (0.10–0.15 SD)  Melody, Pad, Bass                 Perc dropped
Step 3 (0.06–0.10 SD)  Pad, Bass                         Melody dropped
Step 4 (< 0.06 SD)     Pad only                          Bass dropped
Step 5 (The Reading)   Room tone only (0 layers)         Pad dropped
```

---

## 3. Technical & Audio Engine Specification

### 3.1 File & Sample Format
- **Sample Rate**: `48,000 Hz` (48 kHz, native iOS audio hardware output match).
- **Bit Depth**: `24-bit` uncompressed Linear PCM.
- **Channels**: Stereo (`2 channels`).
- **Container / Format**: `.caf` (Apple Core Audio Format) or `.wav`.
- **Exact Loop Sample Count**: At 84 BPM, 16 bars = $\frac{16 \times 4 \times 60}{84} \times 48000 = \mathbf{2,194,286\text{ samples}}$. All 5 stem files must have this exact sample length to avoid phase drift over 13 minutes of continuous looping.

### 3.2 Playback Engine (`AVAudioEngine`)
1. Create five `AVAudioPlayerNode` instances connected to a single `AVAudioMixerNode`.
2. Load each stem into an `AVAudioPCMBuffer`.
3. Schedule buffers on all 5 nodes simultaneously with the `.loops` option before playback starts:
   ```swift
   for node in playerNodes {
       node.scheduleBuffer(stemBuffer, at: nil, options: .loops)
   }
   engine.start()
   playerNodes.forEach { $0.play() }
   ```
4. Layer removal is performed by ramping the player node's `volume` parameter.

### 3.3 Fade Dynamics
- **Fade Duration**: **2,500 ms (2.5 seconds)**.
- **Fade Curve**: Equal-power (quarter-sine or cosine taper $V(t) = \cos(\frac{\pi}{2} \cdot \frac{t}{T})$) to avoid perceived volume dips or clicks.
- **Hard Cuts**: Strictly prohibited.

---

## 5. Reference material — Obsession (2026), "Love Is In The Air" pt. 1 & 2

Requested in `SPEC-GAME.md` §7 as the new direction. Neither the session that
wrote §7 nor this one has heard the track; the user supplied a guitar tab and
a piano transcription instead of a description or audio file, so what follows
is read off those documents, not off the recording. **Audio work itself is
out of scope for this session** (see `HANDOVER-GAME.md` / `AGENT-LOG.md`,
2026-09-01 session) — this section only preserves the reference so it is not
lost before the session that implements §7.

**Source 1 — guitar tab** ("Obsession - Love Is In The Air Pt 1 Intro Tab",
arr. unknown tab author). Standard tuning (EADGBE), capo 3rd fret. The intro
is a fingerpicked arpeggio: alternating bass note (open low string) against a
repeating treble figure with a pull-off (`3-1` on the B string), i.e. a
Travis-picking-style pattern, not strummed chords. The verse settles into a
steadier eighth-note bass pulse under the same pull-off figure.

**Source 2 — piano transcription** ("love is in the air, pt. 1", obsession //
rock burwell, arr. zon; screenshot supplied by the user). Concrete numbers
read directly off the sheet:
- **Tempo: ♩ = 57.** Roughly *two-thirds* the current loop's 84 BPM — this is
  a slow, unhurried piece, not a walking-pace folk tune.
- **Time signature: 4/4.**
- **Key signature: two flats** (B♭ major / G minor) — consonant with the
  guitar tab's capo-3 open-chord shapes transposing up a minor third.
- **Texture:** continuous 16th-note broken-chord arpeggios in the left hand
  under a sparse right-hand melody — closer to *contemplative and searching*
  than *bright and forward-moving*. A measure in the second system is
  highlighted in the source screenshot; the user flagged nothing there, so it
  is not being treated as an error or as separately significant.

**What this means for §8.1, flagged and not resolved here:** the current
spec (§1.1 above) is 84 BPM **D Dorian**, explicitly "playful," "carefree,"
"forward momentum." The reference is ~57 BPM, **B♭ major or G minor**, and
arpeggiated/contemplative rather than pulse-driven. Porting the reference
faithfully is a **tempo and mode change**, which `SPEC.md` §8.1 forbids mid
-session but does not forbid choosing once, before ship. `SPEC-GAME.md` §7's
own note applies: if the reference turns out texture-driven rather than
riff-driven (it reads that way from these two sources), the stem-removal
schedule may need to become a filter/density schedule instead of a
layer-count schedule — **that is a `SPEC.md` change**, to be made in the
session that actually implements audio, not assumed here.

Not yet known from these sources: the two parts' relationship (pt. 2 as
variation, continuation, or reharmonisation of pt. 1 — not supplied), or
timbral choices (this is a guitar/piano reference; the existing stems are
glockenspiel/shaker/nylon-guitar/upright-bass/string-pad, and nothing here
says whether that instrumentation carries over or should change with the
mood).

**Separately, mood/technique research.** The user also asked (independent of
the pt. 1/pt. 2 reference above) for research into what makes music read as
"upbeat and warm but subtly out of tune, eerie, and cautious," and into
adaptive/procedural systems that make replays genuinely unpredictable —
explicitly in tension with this file's §1.1 "never change key or tempo,
only remove layers, never add back" rule. That research (item list, field
framework, full web-search supplement with sources) is in
`priors-audio-direction/` at the repo root — start there, not from scratch,
when §7 is actually implemented. Two findings from it worth reading first:
hauntology/Ghost Box Records is the closest genre match to the requested
mood, and Eno's coprime tape-loop lengths / Lutosławski's controlled
aleatorism both produce unbounded per-playthrough variation inside a fully
locked key and tempo — i.e., mechanisms that may satisfy "unpredictable" and
"remove-only" simultaneously, which is the open tension this file's rule
creates.

---

## 6. Legal & Licensing Verification: GarageBand Apple Loops

- **Status**: **100% Royalty-Free for Commercial and Non-Commercial Games.**
- **Source**: [Apple Legal Support: Using royalty-free loops in GarageBand](https://support.apple.com/en-us/HT201808) & *Software License Agreement for GarageBand* (§2.C):
  > *"You may use the Apple and third party audio loop content (Audio Content), contained in or otherwise included with the Apple Software, on a royalty-free basis, to create your own original soundtracks for your video and audio projects... You may not distribute the Audio Content on a standalone basis."*
- **Application to Priors**: Composing the 5-layer stems using GarageBand / Logic Pro built-in instruments and Apple Loops creates an original game soundtrack and complies with all licensing requirements without royalty obligations.
