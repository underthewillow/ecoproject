# Pond

A single-sitting ecosystem simulator prototype, built in Godot 4.7. The player starts with
bare water and introduces every organism themselves, shaping a pond that evolves under the
pressures they create. See [`docs/pond-prototype-plan.md`](docs/pond-prototype-plan.md) for
the full design brief.

This repo was built as two parallel, deliberately decoupled tracks that have since merged
partway:

- **Track A** — a pure, headless, deterministic simulation core. No rendering dependencies,
  no player-facing code. Runs and validates entirely from the command line.
- **Track B** — a look/motion/audio study: painterly top-down visuals and generative
  procedural audio, originally developed against fake placeholder data so it never had to
  wait on Track A.

The visual side of the merge (Phase 6) has happened: `render/look_study/look_study.tscn` is
now the actual playable prototype, reading a real `SimCore` instead of fake population data,
and owns the two player verbs (introduce a species, add nutrients) plus the difficulty
toggle. Audio has *not* merged yet - `render/audio/pond_audio.gd` still reads
`render/fake_pond_state.gd`'s placeholder data independently, which is why that module is
still here. `scenes/debug_chart.tscn` remains as a secondary, numbers-visible tool for
development/debugging - the real chart the design doc describes stayed useful once its
mechanics existed, it just isn't what a player would use.

## Requirements

- [Godot 4.7](https://godotengine.org/) or later (GL Compatibility renderer)
- No other dependencies — everything is plain GDScript, no plugins or addons

## Running it

Open `project.godot` in the Godot editor and run. The default main scene is
`render/look_study/look_study.tscn` - the real playable pond, with buttons to introduce
species, add nutrients, and switch difficulty. `scenes/debug_chart.tscn` is still available
to open and run directly for a numbers-visible view of the same mechanics (raw population
counts, mean daphnia size as a line, capacity as a number) - useful for debugging, not
intended as the player-facing experience.

Track A's real acceptance checks run headless, without opening the editor at all — see
below.

## Repo structure

```
docs/                       Design documents
  pond-prototype-plan.md      The original build brief (design pillars, run shape, §-numbered)
  audio-design-notes.md       Track B audio: music theory, production lessons, architecture,
                               known open items, and full revision history (read before
                               touching render/audio/pond_audio.gd)

sim/                         Track A — headless simulation core
  core/
    sim_core.gd                The step function: algae growth/uptake/mortality, daphnia
                                grazing, fish predation, mass-conserving flows end to end
    sim_config.gd               Tunable parameters (one object per run, so the sweep
                                harness can override values without touching sim_core.gd)
    sim_state.gd                Plain state snapshot (algae/nutrients/detritus/daphnia/fish,
                                plus daphnia's mean body size and per-bin distribution)
    sim_rng.gd                   Seeded RNG — same seed always produces the same run
    trait_bin_population.gd     Generic trait-binned population (bins, mean-trait tracking,
                                offspring redistribution) — species-agnostic; daphnia's
                                size-dependent ecology sits on top of this in sim_core.gd
  harness/                    Headless verification scripts (run via `godot --headless -s`)
    determinism_check.gd        Same seed -> bit-identical output
    equilibrium_check.gd        Algae alone reaches and holds a stable equilibrium
    mass_conservation_check.gd  Total mass stays exactly constant across a full run
    sweep_phase2.gd              Grid-search daphnia/algae params for sustained oscillation
    phase2_validate.gd          Confirms the chosen combo holds over a full ~90 sim-min run
    sweep_phase3.gd              Grid-search fish params for three-trophic-level persistence
    phase3_validate.gd          Confirms the chosen combo across 20 seeds
    sweep_phase4.gd              Grid-search daphnia's size-dependent exponents, scored by
                                the mean-size gap between with-fish and without-fish runs
    phase4_validate.gd          Confirms the chosen combo across seeds and full duration,
                                including a single run that introduces then removes fish
    phase5_validate.gd          A scripted "naive policy" (introduce whichever species is
                                missing, in order, as capacity allows) proxies the human
                                legibility claim headlessly: does it reach three-trophic
                                coexistence and stay alive across a full session?
    decomposer_apex_predator_check.gd  Backlog scaffold check (not a numbered phase) for a
                                detritus-eating decomposer and fish-eating apex predator -
                                both gated off by default (sim_config.gd's enable_decomposer/
                                enable_apex_predator); confirms mass conservation and no
                                NaN/negative blowups, not a tuned or shipped mechanic yet
  species/                    Currently empty — reserved for a possible future species
                                beyond daphnia/fish/algae; see docs/pond-prototype-plan.md §9

scenes/
  debug_chart.tscn / .gd      Track A's live line chart of raw sim state, plus the same two
                               player verbs as look_study - a numbers-visible development
                               tool now that look_study.tscn is the player-facing scene.

render/                      Track B — look/motion/audio study, now partially merged with
                               Track A (Phase 6 - visuals only; audio hasn't merged yet)
  look_study/
    look_study.tscn / .gd       The real playable prototype: painterly top-down pond reading
                                a real SimCore, algae/daphnia/fish rendered from generated
                                sprites, cosmetic predation, daphnia sprite size following the
                                real mean-trait evolution signal (§4.2), capacity/nutrient/
                                detritus shown as a glow/tint/silt-density rather than
                                numbers (§7), and the introduce-species/nutrient/difficulty
                                controls (ported from debug_chart.gd)
  fake_pond_state.gd            Shared fake population-count formula - look_study.gd no
                                longer reads this (see above), but pond_audio.gd still does;
                                wiring audio to real state is a separate, not-yet-done step
  pond_events.gd                One-way signal bus (autoload) - the renderer announces
                                cosmetic predation events and real collapse events without
                                depending on the audio system, and vice versa (nothing
                                listens to the collapse signal yet - see fake_pond_state.gd
                                above, audio hasn't merged)
  audio/
    pond_audio.gd / .tscn       Fully procedural/synthesized ambient audio (no pre-rendered
                                or AI-generated clips) - drone, generative pad voices, a
                                walking bass, and event-driven chimes. See
                                docs/audio-design-notes.md before changing this.
    audio_render_check.gd       Headless harness: renders the real audio scene to a WAV
                                and checks it (silence/clipping/NaN/timing latency/energy
                                trend over time) — the only verification possible without
                                a human ear
  sprites/, water/             Generated art assets (fish, daphnia, algae, lily pads,
                                rocks, pond background)

project.godot                 Godot project config; also registers the pond_events
                               autoload
```

## Track A status

Phases 0-5 are implemented and passing their headless acceptance checks: deterministic
core, algae-alone equilibrium, sustained daphnia/algae predator-prey oscillation,
three-trophic-level persistence (algae → daphnia → fish), daphnia trait-bin evolution, and
now the player layer — introduce a species with a chosen founder size, one pond-capacity
resource that regenerates faster the more trophic levels are currently coexisting (not just
from raw biomass - a single thriving species isn't rewarded the same as a genuinely balanced
web), a nutrient lever, and a collapse/restart mechanic ("no hard fail state" - a crashed
pond resets to a hardier producer-only base rather than ending the run) — each validated
over a full ~90 simulated-minute run, not just a short exploratory window.

Phase 5 is genuinely a headless-mechanics-first pass: Track A still has no rendering
dependencies of its own, and the debug chart's new buttons are a bare-bones exception built
specifically so the sim is clickable at all before Track B's real UI/art exist at the
Phase 6 merge. Its acceptance criterion ("a person who's never seen the game can reach
Act 3 without instruction") is a human-legibility claim that a headless check can't fully
settle - `phase5_validate.gd` checks a scripted proxy instead: a "naive policy" that only
knows the design doc's own stated rules (introduce algae → daphnia → fish in order, spend
capacity as it allows, top up nutrients when low, and if the pond ever collapses, notice
and reintroduce whatever's missing) reaches three-trophic coexistence and is still alive at
the end of the session, across 20 seeds, with zero knowledge of the sim's internal tuning
constants. Whether it's actually *legible* to a real stranger is a question for after
Phase 6, once there's a real interface to hand someone.

Direct playtesting found the default pace outrunning reaction time, so `SimConfig` now has a
`Difficulty` preset (Challenging/Casual/Relaxing, at 1x/0.5x/0.25x) that applies a single
time-dilation multiplier to every ecological rate at once (see `sim_core.gd`'s
`_step_ecology`/`_step_daphnia_bins`, which compute `TICK_DT * pace_scale` in place of the
bare tick constant wherever a flow gets applied). Scaling every rate uniformly is a pure
similarity transform - the same oscillations and collapses happen, just stretched out - so
it needed no re-tuning of the Phase 2-4 sweeps; `phase5_validate.gd` confirms the naive
playthrough still reaches and survives Act 3 under all three presets (Relaxing takes about
4x as many ticks to reach Act 3 as Challenging, matching the transform exactly). The debug
chart has live buttons for all three so they can be A/B'd in one sitting.

One real finding from building this: dropping a daphnia founder into an algae population
that's already grown large and unaccompanied (rather than growing together from small
values, the only regime Phase 2's own sweep ever validated) can trigger an explosive
population boom that grazes algae to extinction in a few hundred ticks. Phase 5's founder
counts and economy pacing deliberately keep introductions close together in both time and
magnitude to stay inside the proven-stable regime; the collapse/restart mechanic exists
precisely because even inside that regime, this ecology can still eventually crash on its
own after a long healthy run - which is a feature (§1's "a story, not a game over"), not a
bug, as long as the pond actually recovers afterward instead of staying stuck.

A detritus-eating decomposer and a fish-eating apex predator (docs/pond-prototype-plan.md
§9) now have a mass-conserving headless scaffold - both gated off by default
(`enable_decomposer`/`enable_apex_predator` in `sim_config.gd`), so the shipped loop and
every other harness are unaffected by their existence. This is intentionally not a tuned or
shipped mechanic - see `decomposer_apex_predator_check.gd`'s own header for what it does and
doesn't check.

Run any acceptance check directly:

```
godot --headless --path . -s res://sim/harness/determinism_check.gd -- --seed=42 --ticks=1000
godot --headless --path . -s res://sim/harness/equilibrium_check.gd -- --seed=42 --ticks=20000
godot --headless --path . -s res://sim/harness/mass_conservation_check.gd -- --seed=42 --ticks=54000
godot --headless --path . -s res://sim/harness/phase2_validate.gd -- --seed=42 --ticks=54000
godot --headless --path . -s res://sim/harness/phase3_validate.gd
godot --headless --path . -s res://sim/harness/phase4_validate.gd
godot --headless --path . -s res://sim/harness/phase5_validate.gd
godot --headless --path . -s res://sim/harness/decomposer_apex_predator_check.gd
```

The three sweep scripts (`sweep_phase2.gd`, `sweep_phase3.gd`, `sweep_phase4.gd`)
grid-search parameters and write results to `sweep_results/` (gitignored — regenerate
rather than commit).

## Track B status

**B1 (motion) and B2 (water/light)** are functionally done with a painterly, top-down,
generated-sprite art direction. The known fish-tail seam artifact (a highlight on the source
art not lining up across the body/tail crop boundary during the wobble animation) is fixed
by feathering the tail's alpha near the seam so the body shows through the blend zone,
rather than regenerating art - see `_draw_fish_tail_feathered` in `look_study.gd`. The
direction itself is still not considered permanently final, but is stable enough to have
been merged with real data (see below).

**B3 (audio)** went through ten iterations of listening feedback and landed on a working,
research-grounded stopping point: real minor-pentatonic/blues-scale music theory, a
three-bus mix (a dry foundation for the drone/bass, a reverberant bus for the textural
pad/chime layers, a shared limiter), and a walking bass line. It's explicitly **not
final** — read [`docs/audio-design-notes.md`](docs/audio-design-notes.md) in full before
changing it; it documents every principle, bug, and dead end from that process so they
don't need to be rediscovered. Audio still reads `render/fake_pond_state.gd`'s placeholder
numbers, unaffected by the visual merge below.

**Phase 6 (merge, visuals only)** is done: `look_study.tscn` reads a real `SimCore` instead
of fake data, and is now the project's default scene and the actual playable prototype (see
"Running it" above). What changed, mapped to the design doc's own §7 list of "four things a
player should diagnose by looking":

- **Water clarity / population health** — real populations drive particle counts near 1:1
  (`_resize_to_population` in `look_study.gd`), not through a normalized/log-scaled curve -
  direct playtesting feedback was that introducing e.g. 2 daphnia should show close to 2
  daphnia, not a count squashed through a "how full should the screen look" formula.
  Populations are continuous (§4.1's trait bins track density, not headcount), so a
  fractional remainder renders as one additional individual at reduced size that grows as it
  approaches the next whole number - reproducing into existence becomes visible growth
  rather than a sudden pop-in. Silt (tied to detritus, see below) is not a species a player
  introduces by founder count, so it kept the earlier reference-scale/log-curve treatment.
- **Nutrient load** — a full-scene translucent water tint, not a number
- **Detritus accumulation** — the existing silt particle system's density now tracks real
  detritus instead of being a fixed decorative count
- **Trait evolution (§4.2, Phase 4's whole point)** — daphnia sprite size now follows real
  mean body size, so "fish are shrinking the daphnia" is something visible in the pond
  itself, not just a line on the debug chart
- **Capacity (§6.3)** and **collapse events (§1 pillar 3)** aren't in that original four-item
  list, but needed the same treatment: capacity is a glowing orb (fits the existing
  "bioluminescent" direction better than a bar/dial would) rather than a number, and a
  collapse triggers a brief full-pond flash rather than being invisible outside the debug
  chart's line graph

**A cross-track lesson from playtesting**: tying eat-flash frequency to the real
grazing/predation rate (above) removed the old per-predator cooldown that used to
incidentally space cosmetic "eating" events out. `pond_audio.gd`'s interaction chimes are
deliberately un-throttled on the audio side (round-robin voices, no cooldown - see its own
comment: an earlier single-voice design silently dropped events, which was worse), on the
assumption that events arrive at a naturally spaced pace. Without the old cooldown, several
daphnia converging on the same algae (their own chase-the-nearest behavior encourages this)
could release a small backlog of banked eat-credit in a near-simultaneous burst, hitting all
3 chime voices back-to-back before any had decayed - reported directly as "crunch/clipping
distortion sounds throughout the game." Fixed with a global (not per-predator) minimum
interval between eat-flash events, independent of the credit system - the average rate
still tracks real consumption, but bursts get smoothed into a steady trickle. Verified
technically (spacing between events, no gaps under 0.2s even in an aggressive
15-daphnia/abundant-algae stress scenario) - actually confirming it sounds right is, like
the rest of B3, outside what I can check myself.

§7's "numbers stay hidden by default" is still the long-term intent, but direct playtesting
feedback was that the numbers are needed *right now* to judge whether any of this is tuned
sensibly - `look_study.gd` draws the raw values as text too (`NUMERIC_OVERLAY_ENABLED`),
meant to come back off once there's enough played experience to trust the visual gauges
alone.

I can't visually judge whether any of this actually looks *right* - same ceiling as the
audio work, where every check was technical (does it run without errors, are the numbers in
sane ranges) rather than a judgment of quality. Worth actually playing before trusting it.
