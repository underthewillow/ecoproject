# Pond

A single-sitting ecosystem simulator prototype, built in Godot 4.7. The player starts with
bare water and introduces every organism themselves, shaping a pond that evolves under the
pressures they create. See [`docs/pond-prototype-plan.md`](docs/pond-prototype-plan.md) for
the full design brief.

This repo is being built as two parallel, deliberately decoupled tracks:

- **Track A** — a pure, headless, deterministic simulation core. No rendering dependencies,
  no player-facing code. Runs and validates entirely from the command line.
- **Track B** — a look/motion/audio study: painterly top-down visuals and generative
  procedural audio, developed against fake placeholder data so it never has to wait on
  Track A. The two get merged in a later phase, once each is independently solid.

Neither track currently depends on the other. The renderer and the audio system read fake
population data through a shared, tiny module rather than the real simulation, so both can
be iterated on (and this repo run) without the other being finished.

## Requirements

- [Godot 4.7](https://godotengine.org/) or later (GL Compatibility renderer)
- No other dependencies — everything is plain GDScript, no plugins or addons

## Running it

Open `project.godot` in the Godot editor and run. The default main scene
(`scenes/debug_chart.tscn`) is Track A's live debug chart (see below); to see Track B's
visual/audio study instead, open and run `render/look_study/look_study.tscn` directly.

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
  species/                    Currently empty — reserved for a possible future species
                                beyond daphnia/fish/algae; see docs/pond-prototype-plan.md §9

scenes/
  debug_chart.tscn / .gd      Track A's live line chart of raw sim state, plus (Phase 5) a
                               minimal interactive panel for the two player verbs - introduce
                               a species with a chosen founder count, add nutrients - so the
                               sim is actually clickable ahead of Track B's real UI/art. The
                               project's current default scene.

render/                      Track B — look/motion/audio study
  look_study/
    look_study.tscn / .gd       The visual study: painterly top-down pond, algae/daphnia/
                                fish rendered from generated sprites, cosmetic predation
  fake_pond_state.gd            Shared fake population-count formula - both the renderer
                                and the audio system read this independently, standing in
                                for real Track A state until the tracks merge
  pond_events.gd                One-way signal bus (autoload) - the renderer announces
                                cosmetic predation events without depending on the audio
                                system, and vice versa
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

Run any acceptance check directly:

```
godot --headless --path . -s res://sim/harness/determinism_check.gd -- --seed=42 --ticks=1000
godot --headless --path . -s res://sim/harness/equilibrium_check.gd -- --seed=42 --ticks=20000
godot --headless --path . -s res://sim/harness/mass_conservation_check.gd -- --seed=42 --ticks=54000
godot --headless --path . -s res://sim/harness/phase2_validate.gd -- --seed=42 --ticks=54000
godot --headless --path . -s res://sim/harness/phase3_validate.gd
godot --headless --path . -s res://sim/harness/phase4_validate.gd
godot --headless --path . -s res://sim/harness/phase5_validate.gd
```

The three sweep scripts (`sweep_phase2.gd`, `sweep_phase3.gd`, `sweep_phase4.gd`)
grid-search parameters and write results to `sweep_results/` (gitignored — regenerate
rather than commit).

## Track B status

**B1 (motion) and B2 (water/light)** are functionally done with a painterly, top-down,
generated-sprite art direction, but both are explicitly expected to be revisited — this
isn't considered final art.

**B3 (audio)** went through ten iterations of listening feedback and landed on a working,
research-grounded stopping point: real minor-pentatonic/blues-scale music theory, a
three-bus mix (a dry foundation for the drone/bass, a reverberant bus for the textural
pad/chime layers, a shared limiter), and a walking bass line. It's explicitly **not
final** — read [`docs/audio-design-notes.md`](docs/audio-design-notes.md) in full before
changing it; it documents every principle, bug, and dead end from that process so they
don't need to be rediscovered.

Both tracks read `render/fake_pond_state.gd`'s placeholder population numbers rather than
a real simulation snapshot; wiring the renderer and audio to Track A's actual state is
deferred to a later merge phase, once both tracks are independently solid.
