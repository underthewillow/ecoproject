# Track B Phase B3 — Audio Design Notes

**Status as of 2026-08-02: not currently active in the shipped scene.** After the clipping
investigation in §5 below failed to find a confirmed root cause, `look_study.tscn` was
switched to instance `render/audio/ambient_music.tscn` (a single licensed ambient track)
instead of `pond_audio.tscn`, so the prototype has reliable audio while this is unresolved.
Nothing in this document or in `pond_audio.gd` changed because of that swap - it's still the
intended long-term system, just not wired into the active scene right now. See README's "B3
swapped for a licensed ambient track" section for the swap itself.

Status as of 2026-08-01: **workable, not final.** This is a stopping point after ten
iterations, most of them driven by direct listening feedback rather than getting it right
the first time. The remaining known issue is that overall volume still reads as too quiet
even after several rounds of raising it. Read this document before touching
`render/audio/pond_audio.gd` again — it exists specifically so the next pass doesn't
re-litigate questions that are already settled, and doesn't repeat mistakes that already
cost a round-trip to find.

Everything here is procedural/synthesized in real time via `AudioStreamGenerator` — no
pre-rendered clips, no AI-generated audio (that path was researched and is still available
as a fallback; see §6).

---

## 1. Aesthetic target

Meditation / singing-bowl ambient, with a generative structure inspired by Brian Eno
(*Music for Airports*, *Bloom*/*Reflection*). Not a "song" — no fixed composition, no
melody that repeats identically, nothing that demands attention. The one deliberate
exception is the bass line (§4), added later at the user's request for "a felt sense of
groove while playing."

## 2. Architecture

Three audio buses, all created in code (`_ensure_audio_buses()` in `pond_audio.gd`), not a
committed `default_bus_layout` resource:

```
Drone, Bass                              →  PondFoundation  →┐
Voice1-4, PhraseChime, InteractionChime1-3 →  PondAmbient    →┴→ PondMix → Master
```

- **PondFoundation** — drone + bass. Small, short, dry reverb (room_size 0.25, wet 0.15).
  These two exist to be a clear anchor (a steady pitch, a steady pulse), so they
  deliberately stay drier than everything else.
- **PondAmbient** — the four pad voices and both chime types. The textural wash, where a
  longer reverb tail is appropriate. Low-pass filtered (2200Hz) and moderately reverberant
  (room_size 0.55, wet 0.28, damping 0.75).
- **PondMix** — both branches feed here. Holds the one shared `AudioEffectLimiter` (ceiling
  -1dB), which is why it can't live on either branch alone: the safety net has to see the
  fully combined signal to do its job.

Ten independent `AudioStreamGenerator`-backed voices in total: `Drone`, `Voice1-4`,
`PhraseChime`, `InteractionChime1-3`, `Bass`. Every one of them is just an
`AudioStreamPlayer` node — the explicit pivot-friendliness requirement from the original
plan. If procedural synthesis is ever abandoned, any of these can be repointed at a loaded
`AudioStreamMP3`/`OGG` (e.g. an ElevenLabs-generated clip — a real, working MCP server was
confirmed available for this, see §6) without restructuring the scene or changing the
public API (`play_event()`).

## 3. Music theory principles

**Minor pentatonic, in just intonation, is the palette for everything**
(`PENTATONIC_RATIOS = [1.0, 6/5, 4/3, 3/2, 9/5]` — root, ♭3, 4, 5, ♭7). This was arrived at
after an earlier attempt used an "open chord" of only octaves and fifths (no thirds or
seconds), which was *safe* but read as static and empty. Minor pentatonic is the
genre-standard ambient/meditative scale because it skips semitone-adjacent degrees (the
harshest possible clash is structurally impossible) while still allowing real melodic
movement. It is also, not coincidentally, the basis of the blues scale (see below) — the
same palette serves both the ambient pad texture and the walking bass without needing two
different systems.

**Every pentatonic-degree pair is not equally consonant.** Some adjacent degrees are a
whole tone apart (~180-200 cents) — mild tension when two voices sustain on them at once.
This is normal/expected color for a minor-key palette, not a bug, and doesn't need
"fixing" — it's part of why minor pentatonic sounds different from a bare open chord.

**The blues scale is minor pentatonic plus one added note: a flattened 5th ("the blue
note").** The bass line uses this as an occasional *passing tone* between the 4th and 5th
scale degrees specifically — the one place real blues bass lines put it — and nowhere
else in the system. Two hard-won rules about it:
- It must be **brief**. A real passing tone is short by definition (music theory: passing
  tones connect two stable tones via stepwise motion and don't linger).
- It must be **unaccented**. Non-chord tones conventionally fall on a weak beat, never the
  strong one.
Getting either of these wrong makes the blue note read as a sustained dissonant clash
instead of a quick, idiomatic bluesy touch — this happened for real once the bass became
loud enough to actually hear (v7→v8 transition), and was fixed by giving the blue note its
own much faster decay and forcing it to always use the soft/ghost dynamic.

**Walking bass is built from stepwise motion connecting chord tones, not a repeating
riff.** An early bass implementation used a fixed 8-beat pattern, which read as too
repetitive. The fix was a persistent walking direction that reverses every 2-4 steps (an
"ascend, then descend" contour — the classic blues shuffle shape), not a longer or more
varied fixed pattern.

**Funk's groove comes from dynamics and space, not from more notes.** Concretely: an
accent on "the one" (every direction-reversal/turnaround in the walking bass gets treated
as a strong downbeat), roughly a third of the remaining notes dropped to a soft "ghost
note" level, and real rests (not every beat has a note). Adding more notes or a busier
rhythm would fight the otherwise slow, meditative pace of everything else in the mix.

**The drone never changes pitch.** That's what makes it a drone rather than another pad
voice — its only movement is the slow natural beating from two detuned oscillators a few
cents apart.

**Generative structure**: *Music for Airports* was built from ~22 tape loops of differing
*physical* lengths, cycling "incommensurably" (their loop points never resynchronize).
That's the direct model for the pad voices and the phrase generator: independent,
non-synchronized timers left running against each other, with no fixed composition.

## 4. Production / synthesis principles

**Clean integer harmonics sound cheap; real singing bowls are inharmonic.** A bowl's
overtones sit at non-integer ratios of the fundamental (commonly cited around
2.76×/5.02×/8.2×), not exact multiples. Building a tone from exact 3×/5× harmonics —
mathematically "correct" additive synthesis — is exactly what makes a cheap FM-synth bell
preset sound synthetic. `_bowl_wave()` uses the inharmonic ratios deliberately.

**Register matters more than it seems.** Calming/meditative material generally sits low
(~20-250Hz); singing bowl fundamentals are commonly cited around 200-300Hz. An early pass
had the root at 110Hz with chimes reaching two octaves above that (400-900Hz+) — well
above where this genre actually lives. Root is now 55Hz (A1), with each layer occupying
its own distinct, moderate register rather than any one layer reaching high.

**Dry, unfiltered synthesis reads as cheap regardless of note choice.** Ambient production
leans on real reverb and low-pass filtering to round off harsh highs; this system had none
for its first two passes and it was a major contributor to sounding "cheesy."

**Reverb character is a warmth knob, and it was set wrong.** Small rooms (short decay, low
wet%) read as warm and intimate; large halls (long decay, high wet%) read as cold and
cavernous. An early pass used room_size 0.9 (near-maximum) with 40% wet — closer to a cold
cathedral than a warm room, and directly implicated in a "too cheesy"/"unpleasant" verdict
before the fix.

**Reverb should be reserved for fewer elements; keep rhythmic/foundational material dry.**
Real mixing practice keeps bass and other rhythmic anchors out of long reverb tails
specifically because the tail smears rhythmic definition into mud. Running the drone and
bass through the *same* heavy reverb as the melodic/textural layers was a real mixing
mistake, not just a taste issue — fixed by giving them their own much drier bus (§2).

**A reverb fed by a never-stopping input never actually finishes decaying.** The drone is
always on, so a reverb tail built from it is continuously replenished and never resolves
to silence — a real, well-documented reverb characteristic, and the most likely
explanation for a "sustained feedback loop" impression reported at one point. Verified
directly (not just reasoned about): rendered the drone alone for 60 real seconds and
checked RMS across three time segments — flat, no growth trend, confirming it was not a
literal runaway/unstable buildup, just a large reverb doing what large reverbs do with
continuous input.

**`AudioStreamGenerator.buffer_length` is a real, significant latency knob**, not just a
safety-margin tuning parameter. The default (0.5s) means a freshly-triggered sound queues
up behind up to half a second of already-buffered audio before it's actually heard — for
anything meant to feel tied to a specific instant (the interaction chimes, meant to land
"on the beat" when a predation event happens), this is a serious, very perceptible bug.
Reduced to 0.05s. This was **measured directly** (a `--trigger-at=T` mode in
`audio_render_check.gd` fires one event at a known time and finds its onset in the
recording), not just fixed by reasoning about it, because an earlier fix attempt in this
same investigation (round-robin voices to stop dropped events) had *not* actually solved
the timing complaint, which is exactly why the latency theory needed real verification
before being trusted.

**An instant envelope jump causes an audible click, which is easy to mistake for
"clipping" — but resetting `note.age` to 0 on retrigger does NOT by itself guarantee
one.** The original fix here (an attack ramp computed from `note.age`) has a gap: age
resetting to 0 makes the *formula* read near-zero, but if the previous note was still
audible above that when the new one triggered, the actual applied sample still jumps
from that leftover value down to the new near-zero one in a single sample — a real
discontinuity the age-based formula alone can't see. Confirmed this mattered in practice
for the bass specifically: `BASS_DECAY_RATE` gives it a ~5.4s natural decay against a
0.9s beat interval, so most beats retrigger a note still ringing at meaningful amplitude.
The actual fix is `note.smoothed_envelope`, a one-pole filter that chases the formula's
target value over `ENVELOPE_SMOOTHING_TIME` instead of jumping straight to it — that's
what makes every transition continuous, retrigger or not (`_advance_note()` and
`_fill_bass()`'s own inline copy of the same logic both work this way now).

**Per-layer clamping does not prevent the mix from clipping.** Each voice's own DSP output
is clamped to ±1.0 before it ever reaches a bus, but that only protects that layer's own
signal — it does nothing to stop several layers (e.g. three interaction voices plus the
bass pulse plus a phrase note, all peaking at once) from summing past 0dB once they're
mixed together. The real fix is a limiter as the final stage of the combined signal path
(§2), which also means individual layer levels can be pushed for presence without
reintroducing clipping risk.

**Measure levels, don't just guess a new number.** After enough rounds of "too loud" →
"too quiet" → "too loud" on individual layers, `audio_render_check.gd` gained an
`--isolate=<layer>` flag that mutes every other layer so one layer's actual RMS can be
measured against the full mix's RMS directly. This is how the bass being buried at
roughly -14dB below the rest of the mix was confirmed as a real, quantified problem rather
than a subjective impression, and it's a reusable tool for any future level dispute, not
just that one incident.

## 5. Known open items for the next pass

- **"The bass is clipping and getting distorted, and so are other sounds at times"
  (user report on a recorded session) — investigated at length, root cause still
  unconfirmed.** What was actually measured, in order:
  - The real exported video audio has no digital clipping anywhere: whole-file peak was
    -17dBFS, and a custom sample-level click detector (scans for isolated one-sample
    deltas far above the local RMS floor — see `click_detect.gd` in this session's
    scratch work, not checked into the repo) found zero click/dropout events in the
    actual recording, only two edge-of-recording artifacts at the very start/end.
  - Rendering the bass layer alone (`--isolate=Bass`) reproduces a tall, full-spectrum
    (up to ~21kHz) broadband spike on every single note attack, visible in a
    spectrogram. This looked initially like a strong lead, but it turned out to be
    unaffected by `BASS_ATTACK_TIME` (tested 8ms vs. 25ms) or `ENVELOPE_SMOOTHING_TIME`
    (tested 3ms vs. 20ms) — neither change visibly softened it. That means it's not
    explained by the envelope-continuity fix above (which is a real improvement on its
    own merits, just not a fix for *this* symptom), and it may simply be a normal
    time/frequency-resolution artifact of how a spectrogram renders any percussive
    attack transient rather than genuine audible distortion — unconfirmed either way.
  - Forced a burst of 13 overlapping interaction-chime events into an 8-second window
    (deliberately worse than the real per-species eat cooldown would ever allow) to test
    whether multiple simultaneous "other sounds" could push the mix into the limiter:
    peak stayed at 0.298 (-10.5dB), nowhere near the ceiling.
  - Checked the `PondFoundation` bus (drone+bass, pre-limiter) directly against
    `Master` (post-limiter) during a real render: pre-limiter peak was 0.12, meaning the
    limiter never engages under any tested condition — ruling out limiter soft-clip
    saturation too.
  - None of this rules out a real defect — it rules out every specific mechanism
    checked so far (true digital clipping, bus/limiter engagement, envelope
    discontinuity, chime-stacking overshoot). One thing it does NOT rule out: every test
    here ran `--headless`, with none of the real editor/Movie-Maker-recording overhead
    (actual rendering, compositing, input polling) that was present when the reviewed
    session was captured. The fill functions run in `_process()`, so any real frame
    hitch under that extra load could starve `AudioStreamGeneratorPlayback`'s ring
    buffer and produce exactly this kind of artifact in a way no headless test could
    ever reproduce. Worth checking whether the same clip, played from an exported
    release build instead of the editor's debug/Movie Maker capture, still has it —
    that would cleanly separate "real synthesis bug" from "editor-recording overhead."
    This is also not the first report of this general shape — README documents an
    earlier "crunch/clipping distortion sounds throughout the game" report that was
    addressed with a global eat-flash cooldown, verified only by event-spacing
    measurement, explicitly not by ear. Worth treating this as possibly the same
    underlying issue resurfacing rather than a fully independent one.
- **Overall volume still reads as too quiet as of this writing**, even after a broad
  make-up-gain pass on both bus branches (+6dB each, applied before the shared limiter so
  clipping safety is unaffected). This needs a fresh listen — it's possible the right fix
  now is less about raw gain and more about which specific layers are perceptually
  carrying "presence" (see the reverb/EQ principles above).
- No formal loudness target was ever established (e.g. a target RMS or LUFS figure) — every
  round has been "does this feel right," which is why it's taken this many passes. Picking
  a concrete numeric target before the next round of tuning might shortcut some of the
  back-and-forth.
- The interaction-chime → predation-event wiring (`render/pond_events.gd`) is a real,
  working one-way signal bus and a reasonable model if Track A's real simulation ever needs
  to feed audio events post-Phase 6 — it doesn't need to change, just gain new callers.
- Nothing here has been checked against Track B's visual/motion tuning (B1/B2), which the
  user has separately flagged as likely to be revisited. If the sprite/background art
  changes meaningfully, it's worth another joint look/listen rather than assuming the audio
  and visuals still feel matched.

## 6. Fallback path (if procedural synthesis is ever abandoned)

ElevenLabs was researched mid-project as a real, working MCP-based sound-generation
service (confirmed to have genuine sound-effect generation, not just speech). Because
every voice here is a plain `AudioStreamPlayer`, swapping any one of them (most likely the
interaction chimes or the phrase generator, since those are the most "special-event"-like)
for a loaded generated clip would not require restructuring this scene.

## 7. Revision history

| Pass | What changed | Why |
|---|---|---|
| v1 | First procedural pass: pentatonic scale, filtered-noise water bed, milestone-gated single-tone chime | Initial build |
| v2 | Two-stage-filtered noise, free-running chime timer, multi-note phrases | Fix "too much static," "chimes too rare" |
| v3 | Dropped the scale for an octaves/fifths-only "open chord"; real detuned-sine drone replacing noise; inharmonic-ish partials; fixed envelope click bug; added interaction chimes via a new event bus | User explicitly proposed "open chord" + singing-bowl reference after research request |
| v4 | Switched to minor pentatonic (proper scale, not just a chord); root lowered 110→55Hz; inharmonic bowl partials tuned to research-cited ratios; added real reverb + low-pass bus | "Still cheesy," "too high," asked to ground in research |
| v5 | Fixed interaction chimes being silently dropped (single voice + cooldown → 3 round-robin voices); added first bass layer (fixed 8-beat pattern) | "Chimes missing/mistimed," volume too low, requested a bassline |
| v6 | Found and fixed `buffer_length=0.5` latency bug (→0.05s), verified by direct measurement; gave bass its own filtered-sawtooth synthesis; added the shared limiter | Chime timing still off after v5's fix; bass needed its own timbre; levels raised enough to risk real clipping |
| v7 | Rebuilt bass as a real walking line (persistent direction, blue note passing tone, funk dynamics); triangle/sawtooth blend replacing raw sawtooth | Bass was "too loud, goofy, too repetitive"; asked to ground in blues/funk theory |
| v8 | Raised bass gain ~7dB after measuring it was ~14dB below the mix | Bass became inaudible after v7's "make it subtle" fix overshot |
| v9 | Split one reverb bus into three (PondFoundation/PondAmbient/PondMix); gave the blue note its own fast/unaccented envelope; warmed bass tone further | "More dissonance," "sustained feedback loops"; verified reverb wasn't literally unstable, fixed the mix architecture and the passing-tone treatment anyway |
| v10 | +6dB make-up gain on both bus branches (before the limiter) | Still described as "too quiet" — good stopping point otherwise |
| v11 | Added `note.smoothed_envelope` (real fix for age-reset-doesn't-guarantee-continuity, see §4); extensively measured but did NOT confirm a root cause for reported clipping/distortion — see §5 | User reported clipping/distortion in a recorded session |

## 8. Sources consulted

- [How Singing Bowls Work: Physics, Harmonics](https://www.theohmstore.co/blogs/our-stories/how-singing-bowls-work-physics-harmonics-and-the-science-behind-their-healing-power) — inharmonic overtone ratios
- [Heaven of Sound: Fundamentals and Overtones](https://heavenofsound.com/pages/fundamentals-overtones) — bowl fundamental frequency range
- [Unlocking The Power Of Low Frequency Music](https://soundscapehq.com/music-with-low-frequency/) — calming register
- [iZotope: 6 Creative Reverb Techniques](https://www.izotope.com/en/learn/6-creative-reverb-techniques-in-music-production.html) — decay time / wet-mix norms for ambient
- [LANDR: Synth Pads](https://blog.landr.com/synth-pads/) — detuning, filtering for warmth
- [Reverb Machine: Deconstructing Music for Airports](https://reverbmachine.com/blog/deconstructing-brian-eno-music-for-airports/) — Eno's tape-loop technique
- [Learn Jazz Standards: Walking Bass Line](https://www.learnjazzstandards.com/blog/learning-jazz/bass/write-walking-bass-line/) — walking bass construction
- [Online Bass Guitar: Blues Scales](https://onlinebassguitar.com/bass-blues-scales/) — blues scale = pentatonic + blue note
- [SF Conservatory of Dance: Why Does Funk Use Syncopation](https://sfconservatoryofdance.org/blog/why-does-funk-use-syncopation/) — "the one," ghost notes
- [LANDR: Synth Bass](https://blog.landr.com/synth-bass/) — triangle vs. sawtooth warmth
- [Valhalla DSP: Reverbs, Diffusion, Allpass Delays](https://valhalladsp.com/2011/01/21/reverbs-diffusion-allpass-delays-and-metallic-artifacts/) — reverb ringing/sustain behavior
- [iZotope: Mixing for Atmosphere](https://www.izotope.com/en/learn/tips-mixing-for-atmosphere.html) — reserving reverb for fewer elements
- [Master Your Mix: 6 Types of Reverb](https://masteryourmix.com/types-of-reverb/) — small room (warm) vs. large hall (cold)
- [Fundamentals, Function, and Form: Nonharmonic Tones](https://milnepublishing.geneseo.edu/fundamentals-function-form/chapter/15-nonharmonic-tones/) — passing tones are brief and unaccented
