# Web-search supplement — raw findings (2026-09-02)

Full output of the web-search-agent pass that supplemented `outline.yaml`
and `fields.yaml`. Kept verbatim (not summarised) because the per-item
rationale and the source list are the valuable part — `outline.yaml` only
carries one-line notes.

Priority read, per the agent's own closing notes: **Ghost Box/hauntology,
The Wicker Man, Everybody's Gone to the Rapture, The Caretaker's *Everywhere
at the End of Time*, Eno's coprime tape loops, Lutosławski's limited
aleatorism, and bell/carillon inharmonicity.** The first four cover the
aesthetic brief at village scale; the last three solve the actual
constraint (fixed key, fixed tempo, remove-only, still unpredictable) with
mechanisms that already exist and are proven — Eno's loop-length arithmetic
and Lutosławski's controlled aleatorism in particular produce unbounded
per-playthrough variation inside a fully locked harmonic field, which is
close to a solved version of what SPEC.md §8.1 asks for.

One structural observation worth carrying into the design session: nearly
every "cheerful but wrong" reference found is **diegetic** — village
singing, a hummed lullaby, a radio, a bell, an in-fiction band. The
mechanism is usually not "dissonance under consonance" but "correct music,
wrong context or wrong medium." That suggests diegesis should be a
first-class axis for Priors' audio design, not an implementation detail —
and it pairs unusually well with remove-only, since a source going silent
is diegetically explicable (the singing stopped) in a way that a stem
simply fading is not.

---

## Supplementary items (full detail)

### A. Village-specific and folk-diegetic wrongness

- **Ghost Box Records / hauntology** (Belbury Poly, The Advisory Circle, The
  Focus Group, 2004-). The label's founding premise: "a tradition of
  British science fiction with very traditional, quaint little village
  settings where suddenly something really freaky and cosmic appears in the
  middle of it." Built from library music, public-information-film
  timbres, and children's-TV synth idiom. Also supplies the critical
  vocabulary (Mark Fisher, Simon Reynolds) around hauntology.
- **The Wicker Man (1973), Paul Giovanni.** The canonical *diegetic* village
  model — cheer is entirely in-world (villagers singing "The Landlord's
  Daughter," children at the maypole). Wrongness comes from archaism and
  context, not harmony, and makes villagers read "quirky rather than
  dangerous" — exactly the misdirection a Priors village needs.
- **Everybody's Gone to the Rapture (2015), Jessica Curry.** English village
  where everyone has vanished, scored with Elgar/Vaughan Williams pastoral
  choral writing plus a genuinely algorithmic playback layer. BAFTA Best
  Music. Closest existing shipped game to Priors' premise.
- **Midsommar (2019), Bobby Krlic.** Bright daylight folk-horror, all-analog
  (Moogs, modular, tape loops, 16-player strings to tape), diverging between
  gorgeous melody and near-atonal passages. The major-key, sunlit variant of
  "wrong," complementing the dark-cluster variant (Under the Skin).
- **Kentucky Route Zero (2013-2020), Ben Babbitt + The Bedquilt Ramblers.**
  Splits score into an Eno-esque electronic bed and diegetic
  hymns/bluegrass performed by an in-fiction band — a template for "the
  village has its own music, and the score is a separate ghost under it."
- **Outer Wilds (2019), Andrew Prahlow.** The Signalscope makes music a
  diegetic instrument of information — each traveler's instrument confirms
  they're alive. Banjo chosen specifically for feeling "a little bit
  off-center." Model for encoding player-model state in *who is still
  audibly playing*, which is subtraction-native.

### B. Children's-media pastiche and degradation

- **Don't Hug Me I'm Scared (2011-2022).** The reference for cheerful
  children's-TV song form that curdles; creators state the goal outright as
  "create an unsettling feeling that you can't quite put your finger on
  why" — nearly identical to Priors' design brief.
- **The Caretaker, Everywhere at the End of Time (2016-2019).** Six hours of
  progressively degrading 1930s ballroom loops mapped to dementia stages.
  The most rigorous existing artwork built on a monotonic, remove-only
  degradation arc — no key change, no re-addition, unpredictability from
  decay artifacts. Treat as Priors' structural precedent, not just mood.
- **Boards of Canada.** The production-technique reference: analog synths
  already detuned, then dubbed to tape across generations so wow-and-flutter
  compounds, plus sampled 1970s public-broadcast/children's-TV fragments.
  Concrete signal-chain instructions for "almost in tune" at the *timbre*
  layer rather than the harmony layer.
- **Analog horror audio grammar** (Local 58, The Mandela Catalogue,
  2015-). Codified palette: band-limited lo-fi, tape hiss, wow/flutter,
  emergency-broadcast/numbers-station idiom, music as "artifacts inside the
  fiction." Effective work matches the noise profile to the purported
  medium (cassette hiss ≠ VHS tracking ≠ broadcast static) — a specificity
  rule worth adopting.
- **Doki Doki Literature Club (2017).** Cheerful J-pop-adjacent loops that
  slip out of tune and degrade as the game "breaks." A useful *negative*
  case — loud, overt, fourth-wall-breaking, the opposite end of the
  player-awareness axis from Ghost Box, marking how much wrongness is too
  much.
- **We Happy Few (2018), The Make Believes.** Diegetic 1960s
  Beatles/Stones pastiche enforcing mandatory cheer. Ships the exact
  mechanic Priors could use: the same song plays full and clean in the
  compliant village, distorted and thinned in ruined districts — variation
  by degrading one asset, no re-scoring.

### C. Suburban / lullaby wrongness

- **Rosemary's Baby (1968), Krzysztof Komeda — "Sleep Safe and Warm."** A
  wordless "la-la-la" lullaby waltz recurring in seven variants,
  "nurturing yet sinister," progressively contaminated by sound-effect
  intrusion (baby cries, squeaks). A masterclass in one theme, many
  degradations — variant-based, not layer-additive.
- **Twin Peaks (1990), Angelo Badalamenti.** Lynch's direction was literally
  "slower — slower is more beautiful." Sweet, tonal, reverb-drenched
  material made wrong by tempo drag and dynamics rather than dissonance —
  tempo-*feel* manipulation via arrangement density, available even with
  tempo locked.

### D. Technique / psychoacoustic mechanisms

- **Mistuning perception research** (Lehmann/Graves et al., 2024; Acta
  Acustica 2024). Mistuning detection relies on *both* beating and
  inharmonicity cues (removing either degrades detection); sensitivity is
  *asymmetric* — compressed intervals are detected more easily than
  stretched ones. Practical consequence: detune upward to stay under the
  player's threshold, downward to be noticed.
- **Deliberate detuning as pleasantness** (pipe-organ Celeste, accordion
  Musette; same 2024 Acta Acustica work). Small detunings are engineered
  for sensory pleasantness in real instruments — the mechanism for a
  village that sounds warm and welcoming and is technically out of tune.
  Cheerful and wrong are the same parameter at different magnitudes.
- **Bell and carillon inharmonicity** (minor-third partial, hum tone;
  Hibbert; JASA 2024 "Consonance in the carillon"). Carillon bells are
  tuned with a prominent minor-third partial, historically ill-suited to
  major thirds; mistuned hum tones produce a "squealing" discord against
  the auditory-system-generated strike pitch. A village church bell is a
  *naturally* wrong-sounding, fully diegetic, always-plausible source —
  arguably the ideal Priors soundmark.
- **Shepard tone / Shepard-Risset glissando.** Unresolvable rising or
  falling motion, no key change required, no layer addition required.
  Produces a sense of continuous change while the harmonic field stays
  fixed.
- **Bone-conduction / resonator estrangement — Inside (2016), Martin Stig
  Andersen.** Compositions physically played through a human skull, an
  uncanny timbre "even without post-processing." Reroute familiar material
  through a wrong physical resonator — timbre only, legal under a
  no-key/no-tempo constraint.
- **Microtonal / xenharmonic and just-intonation tuning as an authored
  scale.** A tuning table is a fixed property of the piece, so a
  xenharmonic scale chosen up front is compatible with "never change key"
  while permanently sitting off the player's learned 12-TET expectations.
- **Schafer's soundscape taxonomy — keynote / signal / soundmark** (World
  Soundscape Project, *The Tuning of the World*, 1977). Named slots to
  remove from: keynote (unconscious background), signal (foreground),
  soundmark (community-distinctive). "Cheerful but wrong" can be a village
  whose keynotes are correct but whose soundmark is missing or duplicated —
  removal-only maps cleanly onto this hierarchy.

### E. Adaptive / procedural systems

- **Alien: Isolation (2014), The Flight (Joe Henson & Alexis Smith) + Sam
  Cooper.** Music delivered in "kit form," remixed live against alien AI
  state, with deliberate tension release to prevent fatigue. Closest
  shipped analogue to "audio driven by a hidden model's belief about the
  player." Same sound designer is now building a similarly evolving
  dynamic score for the next Silent Hill.
- **Returnal (2021), Bobby Krlic.** Per-biome main bed with combat/location
  variations that grow or shrink, authored for roguelike non-linear pacing
  — the per-run-variation case beyond Left 4 Dead's model.
- **Mini Metro (2014), Disasterpeace.** Strongest technical model for
  simulation-state sonification: real-time sample triggering driven by line
  count, station types (timbre), occupancy (dynamics), screen position
  (panning), time of day, day of week, weeks elapsed — each simulation axis
  maps to a sound axis, no key/tempo change needed, unpredictability comes
  from the simulation.
- **Animal Crossing (2001-), Kazumi Totaka.** 24 hourly outdoor tracks plus
  re-arrangement by weather — same melody, different instrumentation. The
  reference implementation of "village music that is always the same and
  never the same," one of few precedents at true village scale.
- **Breath of the Wild (2017), Wakai/Kataoka.** Sparse solo piano over long
  silences, spaced so "you're no longer perceiving rhythm, and thus no
  longer anticipating more music." The most important reference for
  Priors' endpoint — proof a remove-only architecture's terminal near-
  silence can be aesthetically strong rather than merely absent.
- **Brian Eno, Music for Airports (1978) — coprime tape-loop lengths.**
  Fragments pre-selected to be mutually non-dissonant, each on a loop of a
  different length, so intersections never repeat. Arguably the ideal
  generative engine for Priors: fixed key, fixed tempo, no layer ever
  re-added, effectively infinite variation from loop-length arithmetic
  alone.
- **Lutosławski's limited/controlled aleatorism (Jeux vénitiens, 1961).**
  Performers play written material with rhythmic freedom and no shared
  pulse, while the composer retains total harmonic control. Formally:
  per-playthrough unpredictability with a locked harmonic field — Priors'
  exact constraint, solved in 1961.
- **Pure Data / "EAPd" as Spore's actual engine.** Pd was the brain
  (deciding what plays when) over sample-based instrumentation — a cheap,
  well-trodden architecture (also libpd, hvcc/Heavy for compiling Pd graphs
  to C) for rule-based scheduling without full middleware.
- **Wwise Interactive Music Hierarchy specifics** — Music Playlist/Switch
  containers, Step mode, Global scope. The re-sequencing half (distinct
  from RTPC continuous mixing) is what actually produces per-playthrough
  unpredictability without touching key or tempo. Global scope guarantees
  non-repetition across game objects.
- **Elias (Elias Software).** Music-first middleware alternative to Wwise —
  segments, transitions, loops, stingers, real-time visual scripting, no
  soundbank build step, composer-facing UI.
- **Unreal MetaSounds + Quartz (UE5).** In-engine procedural DSP graph with
  sample-accurate musical scheduling, first-party and free — now the
  default answer for gameplay-driven procedural music.
- **Manhattan and Klang/K++ (Chris Nash) — ADC 2025.** Hybrid music editor
  plus procedural engine combining pattern sequencing with generative
  features and live data sonification; free dev kits launched on Unity
  Store and FAB in 2025 (*Ars Arcus*, *Future Sound of Bristol*).
- **Nevermind (2015), Erin Reynolds.** Biofeedback horror — computes heart-
  rate variability from webcam/wearable to detect fight-or-flight and
  adapts accordingly. Extends the adaptivity-driver axis into physiological
  signal, genuinely different from telemetry.
- **Luo & Reiss, "Procedural Music Generation Systems in Games"** (arXiv
  2512.12834, Dec 2025). Systematic survey, two-aspect taxonomy naming the
  three live problems as algorithm implementation, music-quality
  assessment, game integration. Academic spine for this research.
- **"The Audio Uncanny Valley: Sound, Fear and the Horror Game"**
  (Grimshaw, Bolton/Aalborg). The actual paper behind the uncanny-valley-
  in-audio concept, paired with recent vocal-uncanny-valley work showing
  uncanniness is driven by deviation from familiar categories, moderated by
  perceived organicness/animacy — predicting a *familiar* village tune
  degraded slightly will out-perform an unfamiliar dissonant one.

---

## Sources

**Hauntology, village-uncanny, degradation**
- [Ghost Box Records (Wikipedia)](https://en.wikipedia.org/wiki/Ghost_Box_Records)
- [Hauntology (music) (Wikipedia)](https://en.wikipedia.org/wiki/Hauntology_(music))
- [Yesterday's Entertainment: The Hauntological Sounds of Ghost Box Records — Horrified](https://www.horrifiedmagazine.co.uk/other/the-hauntological-sounds-of-ghost-box-records/)
- [Weird Britain in Exile: Ghost Box, Hauntology, and Alternative Heritage — Popular Music and Society 35(4)](https://www.tandfonline.com/doi/abs/10.1080/03007766.2011.608905)
- [HAUNTOLOGY: the GHOST BOX label (Simon Reynolds, Frieze 2005)](http://reynoldsretro.blogspot.com/2017/10/hauntology-ghost-box-label-frieze-2005.html)
- [Belbury Poly (Wikipedia)](https://en.wikipedia.org/wiki/Belbury_Poly) / [The Focus Group (Wikipedia)](https://en.wikipedia.org/wiki/The_Focus_Group)
- [Deconstructing the Boards of Canada Sound — Lars Lentz Audio (2025)](https://larslentzaudio.wordpress.com/2025/03/03/deconstructing-the-boards-of-canada-boc-sound-and-music/)
- [Boards of Canada and Otherly Pastoralism — A Year In The Country](https://ayearinthecountry.co.uk/boards-of-canada-the-past-inside-the-present-and-parallel-world-interconnections-with-hauntology-and-otherly-pastoralism-wanderings-11-52/)
- [List of samples used by Boards of Canada — bocpages](https://bocpages.org/wiki/List_of_samples_used_by_Boards_of_Canada)
- [The Caretaker — Everywhere at the End of Time, Tiny Mix Tapes review](https://www.tinymixtapes.com/music-review/caretaker-everywhere-end-time)
- [Six Stages of Dementia — Neuro Health Alliance](https://neurohealthalliance.org/post/everywhere-at-the-end-of-time)

**Film / TV / children's-media pastiche**
- [The Diegetic Folk Horrors of The Wicker Man (1973) — IU Establishing Shot](https://blogs.iu.edu/establishingshot/2023/09/25/the-diegetic-folk-horrors-of-the-wicker-man-1973/)
- [The Wicker Man (soundtrack) (Wikipedia)](https://en.wikipedia.org/wiki/The_Wicker_Man_(soundtrack)) / [Willow's Song](https://en.wikipedia.org/wiki/Willow%27s_Song)
- [The Horror Of Folk: Bobby Krlic's Midsommar Score — The Quietus](https://thequietus.com/quietus-reviews/album-of-the-week/midsommar-ost-bobby-krlic-haxan-cloak-review/)
- [Krlic interview — Vehlinggo](https://vehlinggo.com/2020/01/06/bobby-krlic-midsommar-score-interview/)
- [Sleep Safe and Warm (Wikipedia)](https://en.wikipedia.org/wiki/Sleep_Safe_and_Warm)
- [Rosemary's Baby score review — The Film Scorer](https://thefilmscorer.com/rosemarys-baby-krzysztof-komeda-1968/)
- [The Story Behind the Music of Twin Peaks — GATA Magazine](https://gatamagazine.com/articles/music/the-story-behind-the-music-of-twin-peaks)
- [Meet the minds behind Don't Hug Me I'm Scared — Royal Television Society](https://rts.org.uk/article/meet-minds-behind-dont-hug-me-im-scared-new-puppet-show-will-give-you-nightmares)
- [NME interview](https://www.nme.com/features/tv-features/dont-hug-me-im-scared-channel-4-interview-3306566)
- [What is Analog Horror — StudioBinder](https://www.studiobinder.com/blog/what-is-analog-horror-definition/)
- [Static + Scares — Backstage](https://www.backstage.com/magazine/article/analog-horror-explained-examples-78326/)
- [Disintegration in Doki Doki Literature Club — Epilogue Gaming](https://epiloguegaming.com/disintegration-in-doki-doki-literature-club/)
- [Audio Nasty: Uncanny Sounds in the Work of Peter Strickland — Revenant Journal](https://www.revenantjournal.com/contents/audio-nasty-uncanny-sounds-in-the-work-of-peter-strickland-john-a-riley-woosong-university/)

**Psychoacoustics and tuning**
- [Mistuning perception in music is asymmetric and relies on both beats and inharmonicity — PMC (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11447020/)
- [Targeted detuning aiming for sensory pleasantness: Pipe Organs and Accordions — Acta Acustica (2024)](https://acta-acustica.edpsciences.org/articles/aacus/full_html/2024/01/aacus240029/aacus240029.html)
- [On mistuning detection and beat perception for harmonic complex tones — JASA 152(1)](https://pubs.aip.org/asa/jasa/article/152/1/226/2838245/On-mistuning-detection-and-beat-perception-for)
- [Consonance in the carillon — JASA 156(2) (2024)](https://pubs.aip.org/asa/jasa/article/156/2/1111/3308177/Consonance-in-the-carillon)
- [The musical sound quality of church bells — Hibberts, The Sound of Bells](https://www.hibberts.co.uk/the-musical-sound-quality-of-church-bells/)
- [Hibbert PhD thesis on strike pitch and pitch shifts](https://oro.open.ac.uk/44498/1/bill_hibbert_thesis.pdf)
- [The Shepard Tone: an audio illusion — Nicolas Titeux](https://www.nicolastiteux.com/en/blog/shepard-and-risset-audio-illusions/)
- [Shepard Tone explained — StudioBinder](https://www.studiobinder.com/blog/shepard-tone-illusion/)
- [Xenharmonic music (Wikipedia)](https://en.wikipedia.org/wiki/Xenharmonic_music)
- [Xenharmonic Wiki — Making Microtonal Music](https://en.xen.wiki/w/Making_Microtonal_Music_is_Easier_Than_You%E2%80%99d_Think)
- [The audio Uncanny Valley: Sound, fear and the horror game (PDF)](https://pubs.hkust-gz.edu.cn/index.php?action=attachments_ATTACHMENTS_CORE&method=downloadAttachment&id=26&resourceId=30&filename=887259de23d3b0c39cfc5592acb3bf481d9a20fe)
- ["Out of the Analog Age: Singing Robots and the Uncanny Valley" — ResearchGate](https://www.researchgate.net/publication/392219654_Out_of_the_Analog_Age_Singing_Robots_and_the_Uncanny_Valley)

**Soundscape framework**
- [Acoustic ecology (Wikipedia)](https://en.wikipedia.org/wiki/Acoustic_ecology) / [World Soundscape Project](https://en.wikipedia.org/wiki/World_Soundscape_Project) / [R. Murray Schafer](https://en.wikipedia.org/wiki/R._Murray_Schafer)
- [Chapter 1: The Soundscape — Just Sound Effects](https://justsoundeffects.com/article/chapter-1-the-soundscape/)

**Games and adaptive systems**
- [Jessica Curry on scoring Everybody's Gone to the Rapture — NME](https://www.nme.com/features/jessica-curry-on-soundtracking-everybodys-gone-to-the-raptures-poignant-exploration-of-loss-3218264)
- [VGMO review](https://vgmonline.net/everybodysgonetotherapture/)
- [Alien Isolation's Music: Interview with The Flight — The Sound Architect](https://www.thesoundarchitect.co.uk/theflightinterview/)
- [Audio interview with Sam Cooper & Byron Bullock](https://www.thesoundarchitect.co.uk/alienisolation/)
- [The music of Alien: Isolation — MCV/Develop](https://mcvuk.com/development-news/the-music-of-alien-isolation/)
- [Alien: Isolation's sound designer on the next Silent Hill's evolving dynamic score — PC Gamer](https://www.pcgamer.com/games/horror/alien-isolations-sound-designer-is-working-on-the-next-silent-hill-game-creating-a-dynamic-score-system-that-evolves-as-you-play/)
- [The music of Returnal: interview with Bobby Krlic — PlayStation Blog](https://blog.playstation.com/2021/04/09/the-music-of-returnal-an-interview-with-composer-bobby-krlic/)
- [The Programmed Music of Mini Metro — interview with Rich Vreeland, Designing Sound](https://designingsound.org/2016/02/18/the-programmed-music-of-mini-metro-interview-with-rich-vreeland-disasterpeace/)
- [Disasterpeace blog — Mini Metro procgen posts](https://disasterpeace.com/blog/tag.procgen.Mini+Metro)
- [Animal Crossing Music: The Ultimate Sonic Guide](https://www.playanimalcrossing.com/animal_crossing_music/)
- [Animal Crossing music extension adapts to local weather — TheGamer](https://www.thegamer.com/animal-crossing-music-chrome-extension-adapts-to-local-weather/)
- [Breaking the Loop: The Cinematic Music of Breath of the Wild — Game Developer](https://www.gamedeveloper.com/audio/breaking-the-loop-a-look-at-the-cinematic-music-of-breath-of-the-wild)
- [Composing Campfire SF with Andrew Prahlow — The Companion](https://www.thecompanion.app/outer-wilds-andrew-prahlow/)
- [Exploring the musical legacy of Outer Wilds — Game Developer](https://www.gamedeveloper.com/audio/everything-but-lost-exploring-the-mesmerising-musical-legacy-of-outer-wilds)
- [How Ben Babbitt scored a Lynchian modern classic (Kentucky Route Zero) — FACT](https://www.factmag.com/2016/08/23/kentucky-route-zero-ben-babbitt/)
- [Audio Design Deep Dive: Using a human skull to create the sounds of Inside — Game Developer](https://www.gamedeveloper.com/audio/audio-design-deep-dive-using-a-human-skull-to-create-the-sounds-of-i-inside-i-)
- [The Sound of Silent Hill 2 (ResearchGate)](https://www.researchgate.net/publication/398025419_The_Sound_of_Silent_Hill_2_An_Exploration_of_the_2001_Original_and_2024_remake)
- [Scoring Silent Hill 2 with Akira Yamaoka — Sonic State (Aug 2025)](https://sonicstate.com/news/2025/08/14/composer-akira-yamaoka-on-scoring-silent-hill-2/)
- [The Make Believes — We Happy Few Wiki](https://we-happy-few.fandom.com/wiki/The_Make_Believes)

**Generative composition and tooling**
- [Deconstructing Brian Eno's Music for Airports — Reverb Machine](https://reverbmachine.com/blog/deconstructing-brian-eno-music-for-airports/)
- [Open Culture](https://www.openculture.com/2019/07/deconstructing-brian-enos-music-for-airports.html)
- [Brian Eno on Spore and generative systems — CDM](https://cdm.link/brian-eno-with-wright-on-spore-and-generative-systems-sound-and-paintings/)
- [Spore & SimCell analysis (Pure Data implementation)](https://mb4thyear.wordpress.com/2017/12/02/spore-simcell-analysis/)
- [Lutoslawski's "Controlled Aleatorism": Strategies and Methods — Opusmodus forum](https://opusmodus.com/forums/topic/3774-lutos%C5%82awski%E2%80%99s-controlled-aleatorism/)
- [Jeux Vénitiens: Temporal Juxtaposition of Sound Modules — Assaf Shatil](https://assafshatil.com/lutoslawski-jeux-venitiens-1961-temporal-juxtaposition-of-sound-modules/)
- [Style and Thought — Witold Lutoslawski Society](https://www.lutoslawski.org.pl/en/witold-lutoslawski/style-and-though)
- [Wwise-201 Lesson 1: Re-sequencing with Music Playlist Containers — Audiokinetic](https://www.audiokinetic.com/en/learning/videos/_bvus5fijxk/?course=wwise201&lesson=1/)
- [Building the Interactive Music Hierarchy (Wwise User's Guide ch. 22)](https://manualzz.com/doc/o/ul74t/wwise---user-s-guide-chapterandnbsp;22.andnbsp;building-the-interactive-music-hier...)
- [elias.audio — adaptive game audio and music middleware](https://elias.audio/)
- [Adaptive music software roundup — Blips](https://blog.blips.fm/articles/adaptive-music-software-a-round-up-of-the-best-options-for-video-games)
- [Creating Procedural Music with MetaSounds — Unreal Engine docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/creating-procedural-music-with-metasounds)
- [Real-Time Music: Creating Procedural Music From Scratch, Unreal Fest Orlando 2025](https://forums.unrealengine.com/t/talks-and-demos-real-time-music-creating-procedural-music-from-scratch-unreal-fest-orlando-2025/2672465)
- [Level Up! Procedural Game Music and Audio (Manhattan/Klang) — ADC 2025](https://conference.audio.dev/session/2025/level-up/)
- [Chris Nash — ADC speaker page](https://conference.audio.dev/speakers/chris-nash/)
- [Luo & Reiss, Procedural Music Generation Systems in Games — arXiv 2512.12834](https://arxiv.org/abs/2512.12834)
- [Adaptive Music Composition for Games — arXiv 1907.01154](https://arxiv.org/pdf/1907.01154)
- [An adaptive music generation architecture for games — arXiv 2207.01698](https://arxiv.org/pdf/2207.01698)
- [GDC Vault: An Adaptive, Generative Music System for Games (Mayer & Larson)](https://www.gdcvault.com/play/1012710/An-Adaptive-Generative-Music-System)
- [Deep Dive: A framework for generative music in video games — Game Developer](https://www.gamedeveloper.com/audio/deep-dive-generative-music-in-video-games)
- [Nevermind — Biofeedback](https://nevermindgame.com/biofeedback)
- [Biofeedback-based horror game challenges players to deal with fear — New Atlas](https://newatlas.com/nevermind-video-game-biofeedback-stress-levels/29728/)

---

## Caveats from the search pass, kept verbatim

- Evidence quality is uneven. Bell-acoustics, mistuning, and carillon-
  consonance sources are peer-reviewed and strong. Most 2026-era "AI game
  music" material found was vendor content marketing unsupported maturity
  claims — not cited as evidence real-time neural generation is
  production-ready. The credible 2025-era items are the ADC 2025
  Manhattan/Klang kits, the Unreal Fest 2025 MetaSounds+Quartz talk, and
  the Luo & Reiss survey.
- Red Dead Redemption 2's score is a partial gap: interviews confirm three
  score types and roughly 60 hours written / 192 interactive mission
  tracks, but the specific claim that stems share a locked key/tempo grid
  for seamless swapping — the part relevant to Priors — could not be
  verified and needs primary sourcing before being treated as fact.
