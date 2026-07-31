# Pond — Prototype Plan

A single-sitting ecosystem simulator. The player starts with bare water and introduces
every organism themselves, shaping a pond that evolves under the pressures they create.

This document is the build brief for the prototype. It is deliberately narrow: it
specifies the smallest system that proves the concept, and explicitly defers everything
else.

---

## 1. Design pillars

1. **Real ecology decides the rules; game design decides what's visible.** The simulation
   can be faithful as long as the player never has to read an equation. Any mechanic whose
   effects can't be seen in the pond itself gets cut.
2. **The player is a selector, not a designer.** They shape conditions and apply pressure.
   The organisms do the evolving.
3. **Calm, not punishing.** No hard fail state. A collapse simplifies the pond and restarts
   succession from a hardier base — a story, not a game over.
4. **Legible cause and effect.** A decision should surface its consequence in roughly
   30–90 seconds. Not instantly, not in twenty minutes.

## 2. Run shape

One sitting, roughly 60–90 minutes, from bare water to a mature pond. Four loose acts,
driven by succession rather than by scripted content:

| Act | State | What the player is learning |
|---|---|---|
| 1 | Bare water, first producers | The gauges; how introductions work |
| 2 | Grazers established | Predator–prey oscillation; the first crash |
| 3 | Predators and competition | Sequencing matters; trait shifts become visible |
| 4 | Maturity | Self-regulation, or firefighting |

Difficulty escalates from the pond's own accumulating nutrient and detritus load, not from
unlocks. (Deferred to post-prototype — see §9.)

---

## 3. Simulation core

### 3.1 Structure

A **pure, headless, deterministic simulation core** with no rendering dependencies.

- Fixed timestep (suggest 0.1 sim-seconds per tick), decoupled from framerate.
- All randomness from a single seeded RNG. Same seed + same inputs = same run, every time.
- The core exposes a state snapshot; the renderer subscribes. The renderer never writes to
  the sim.

This is non-negotiable for the prototype, because tuning a three-species predator–prey
system by feel is close to impossible. See §5 on the sweep harness, and §11.2 for the full
rationale.

### 3.2 Abiotic pond state

Set at run start by the player, then mostly constant for the prototype:

- `light` — drives algal growth
- `temperature` — scales all metabolic and reproductive rates
- `nutrients` (N) — consumed by algae, returned by decomposition
- `detritus` (D) — accumulates from death, slowly remineralises into N

Dissolved oxygen is **deferred** (§9).

### 3.3 Species

Three species for the prototype. This is a complete food chain with a fast-reproducing
lineage sandwiched between a resource and a predator — the minimum setup where evolution
is observable within one sitting.

**Algae** — single biomass value `A`.

```
growth = r_A * A * (N / (N + k_N)) * f(light, temp) * (1 - A / K_A)
```

Consumes N proportional to growth. Death flows to detritus.

**Daphnia** — trait-binned population (see §4). Generation time in seconds; expect 100+
generations per run.

- Ingestion per capita scales with body size (metabolic scaling, roughly `s^0.75`) and
  saturates with food availability: `* (A / (A + k_A))`
- Reproduction from surplus energy; offspring cost scales with `s`, so small individuals
  produce more young
- Baseline mortality plus predation mortality (§4.2)

**Small planktivorous fish** — simple population count `F`. Generation time in minutes;
expect a handful of generations per run. Does not evolve in the prototype.

- Consumption summed across daphnia size bins, weighted by size selectivity
- Grows and reproduces on intake at low trophic efficiency (~10%)
- Starves visibly if intake falls below maintenance

---

## 4. The evolution mechanic

### 4.1 Trait bins, not agents

Do **not** use agent-based simulation. Represent daphnia as a distribution across ~12
discrete body-size bins, each holding a population count — a fractional count, since it's a
density rather than a headcount. Selection moves population mass between bins via
differential survival and reproduction.

*(§11.1 explains why, at length. It's the single most consequential structural choice in
this document — read it before proposing an alternative.)*

This *is* evolution — it's a discretised allele-frequency model — and it is cheap,
deterministic, and runs headless at thousands of ticks per second.

After reproduction, distribute offspring across neighbouring bins with a small spread. That
spread is heritability plus mutational variance, and it's what keeps the population from
collapsing onto a single bin and freezing.

Rendered particles are **cosmetic only**. Map population counts to particle counts with log
scaling and a hard cap. The particles never feed back into the sim.

### 4.2 The tradeoff: competition vs. predation

⚠️ **Correction to an earlier assumption.** I previously described larger daphnia as harder
for fish to eat. That's backwards for planktivorous fish. The real result (Brooks & Dodson,
1965 — the size-efficiency hypothesis) is that visual planktivores *preferentially* eat
**large** zooplankton, which is why fish presence shifts pond communities toward
small-bodied forms.

The accurate version is a better mechanic anyway, because it's a genuine two-sided tradeoff
rather than a straight upgrade:

- **Large daphnia** are more efficient filter feeders and can persist at lower algal
  concentrations — they outcompete small ones when there's no predator. But they are highly
  visible to fish.
- **Small daphnia** are weaker competitors but largely escape visual predation.

Implementation: fish attack rate on a bin increases with that bin's body size. Algal
clearance efficiency per unit biomass also increases with body size.

**The result the prototype exists to demonstrate:** introduce fish and mean daphnia body
size falls over generations. Remove the pressure and it climbs back. If that shift is
legible on screen *without a chart*, the evolution system works and everything later is
elaboration. If it isn't legible, that needs to be known before anything else is built.

---

## 5. Tuning harness

Build this at Phase 2, not at the end.

A headless runner that executes the sim without rendering across a parameter grid and many
seeds, emitting one row per run:

- Did it stabilise, collapse, or flatline?
- Time to each act transition
- Population minima and maxima; oscillation period and amplitude
- Final mean daphnia body size, with and without fish

Predator–prey systems reliably either flatline or explode. Finding the stable band is a
search problem, and a few thousand headless runs will find it far faster than playtesting.

---

## 6. Player mechanics

Two verbs. Resist adding a third in the prototype.

### 6.1 Introduce a species

The pond starts empty. Every organism arrives because the player put it there.

Because nothing is pre-placed, **sequencing is the primary skill** — which maps onto real
community assembly theory and priority effects. Wrong-order mistakes are self-explaining
and need no tutorial:

- Fish before daphnia — the fish visibly starve within seconds
- Daphnia before algae — same lesson, cheaper
- Daphnia with no predator for too long — they graze the algae to nothing and crash the
  pond from the bottom

### 6.2 Founder population size

Each introduction takes one parameter: how many individuals to seed. Cost scales with it.

This is a **genetic bottleneck**, and it's where the introduction system and the evolution
system connect:

- **Large founder** — population initialised across the full spread of trait bins. Plenty
  of variation for selection to act on. Adapts readily.
- **Small founder** — population initialised into a narrow band of bins. Cheap, survives
  fine, but has little raw material — it evolves sluggishly no matter how much pressure the
  player applies.

Implement literally: founder size determines the width of the initial distribution across
bins.

### 6.3 Economy

One currency. It regenerates at a rate proportional to total living biomass, so a healthy
pond funds further introductions. No unlock trees, no cooldowns, no tech tiers in the
prototype — one scarce resource is enough to make sequencing feel weighty, and the point is
to find out whether it *does* before building anything more elaborate.

### 6.4 The one non-introduction lever

Add nutrients. Feeds algae now; becomes the eutrophication mechanic later.

---

## 7. Presentation

Push state onto the **pond**, not onto readouts. Four things the player should be able to
diagnose by looking:

- Water clarity (algal density)
- Nutrient load
- Detritus accumulation
- Population health — fish gasping at the surface, daphnia thinning out

Numbers stay hidden by default. A codex entry unlocks the real science *after* the player
has seen the phenomenon, which is where the biology gets taught without taxing the
moment-to-moment play.

**Debug rendering comes first.** Phase 1–4 need nothing more than line charts of population
and mean trait value over time. The polished pass happens after the sim is proven — but see
§8, Track B: the *look study* runs in parallel from the start, and is not the same thing.

### 7.1 Motion is the aesthetic

A pond reads as alive because of how things move, not how they're shaded. This is the
highest-risk part of the presentation and the part most likely to be under-budgeted.

- **Daphnia hop and jerk.** They're called water fleas for a reason — discrete, erratic
  vertical bursts, not smooth drift.
- **Fish glide, then dart.** Long low-effort coasting punctuated by sudden acceleration.
- **Algae has no agency.** It drifts on currents it doesn't control.

If the particles move like generic game particles, no amount of shader polish rescues it.
The converse also holds: motion that's right looks beautiful with almost no rendering.

Nearly everything else that makes it beautiful is code rather than drawn assets — light
shafts, caustics, refraction, depth fog, silt scatter, surface bloom. There is no character
art, no rigging, no animation cycles. At this scale the organisms genuinely *are* simple
translucent forms, so this is not stylisation away from realism; it's just what a pond
looks like.

### 7.2 Audio

For a calming game, sound is roughly half the aesthetic, and it is the element most often
deferred until it's too late to do well. It belongs alongside the look study, not after it.

- Ambient water movement as the constant bed
- Low tonal drift that shifts with pond state — the audio equivalent of the oxygen gauge
- Discrete, soft event sounds for introductions and population events
- Nothing percussive, nothing that demands attention

The same decoupling that serves the renderer serves audio: it reads pond state and
population counts, and writes nothing back.

---

## 8. Build order

Two tracks, running in parallel. Track A proves the simulation; Track B proves the feel.
They stay independent until Phase 6, which is possible only because the renderer reads
population counts and nothing else.

Each phase has an acceptance criterion. Don't advance until it's met.

### Track A — Simulation

**Phase 0 — Core skeleton**
Fixed-timestep loop, seeded RNG, state snapshot interface, debug line-chart renderer.
→ Deterministic: same seed produces identical output twice.

**Phase 1 — Algae alone**
Growth, nutrient uptake, carrying capacity, death to detritus.
→ Algae reaches a stable equilibrium and stays there.

**Phase 2 — Algae + daphnia (no traits yet)**
Single-body-size daphnia. Build the sweep harness here.
→ Sustained predator–prey oscillation that neither flatlines nor blows up, across at
least 20 seeds. *This is where most of the tuning pain lives.*

**Phase 3 — Add fish**
Three trophic levels, ~10% efficiency, starvation.
→ Three-way system persists 90+ sim-minutes without collapse in the majority of seeds.

**Phase 4 — Trait bins and selection**
12 size bins, size-dependent clearance and predation, offspring spread.
→ Mean daphnia body size measurably falls when fish are present and recovers when they
are removed. Verified across seeds in the harness.

**Phase 5 — Player layer**
Empty pond start, abiotic setup screen, introduce-species with founder size, currency,
nutrient lever.
→ A person who has never seen the game can reach Act 3 without instruction.

### Track B — Look and motion study

**Start this immediately, in parallel with Phase 0.** It is driven entirely by fake
numbers — a sine wave standing in for population counts — because the renderer only ever
needs counts. A few evenings answers the question you care most about, before weeks are
sunk into tuning a simulation for a game that might not feel right.

**Phase B1 — Motion study**
Daphnia hop, fish glide-and-dart, algal drift. Flat colours, no shaders, no lighting.
→ It reads as pond life with zero rendering polish. If it doesn't, fix it here — this is
the cheapest it will ever be to fix.

**Phase B2 — Water and light**
Depth fog, light shafts, caustics, silt scatter, surface treatment.
→ A still frame is something you'd want as a wallpaper.

**Phase B3 — Audio bed**
Ambient water, state-driven tonal drift, soft event sounds (§7.2).
→ Muting it feels like a loss.

### Merge

**Phase 6 — Integration and polish**
Swap Track B's fake numbers for real sim state. Cosmetic layer only — the renderer still
writes nothing back to the sim.
→ The pond is pleasant to watch doing nothing.

---

## 9. Explicitly out of scope for the prototype

Deferred, but the architecture shouldn't foreclose them:

- Dissolved oxygen, eutrophication, and the algal-bloom crash *(the first mechanic that can
  kill everything — add only once Phase 4 is stable)*
- Decomposers as a playable species
- Speciation / lineage branching
- Roster persistence across runs and founder populations from banked lineages
- Multiple pond types (cold tarn, warm farm pond)
- Succession to marsh as a terminal state
- The long-form "tended aquarium" mode

**One thing to protect now:** keep the simulation's time scale a *parameter*, not an
assumption baked into rate constants. The aquarium mode later is the same core stretched
out, and that should not require a rewrite.

---

## 10. Open decisions

- **Tech stack.** Godot (GDScript for gameplay/renderer; consider C# for the simulation
  core if sweep throughput becomes a bottleneck). Requirements: the sim core must be
  runnable headless outside the render loop (`godot --headless`), and fast enough for
  thousands of runs in a sweep.
- **How a run ends.** Two candidates with different emotional shapes: the pond holds itself
  stable without input for some stretch (an achievement), or succession completes all the
  way to marsh (inherently terminal, a little bittersweet, and truer to the biology).
- **The first thirty seconds.** Staring at bare water waiting for algae to take hold is the
  weakest moment in the run and the first thing anyone sees. The abiotic setup probably
  needs to be a decision the player makes rather than a screen they wait through.

---

## 11. Appendix: why these choices

The constraints above are unusual enough that they invite "improvement." This section
exists so that anyone — human or agent — picking up the project understands what each one
is protecting before they reach for something more conventional.

### 11.1 Trait bins instead of agents

**Agent-based** simulation means every organism is an individual object in memory, with its
own position, energy, age, and body size, updated in a loop each tick. It's the intuitive
approach and it's how many ecosystem games work. It is also the wrong choice here.

The problem is population size. A real pond holds daphnia in the tens or hundreds of
thousands. At 10 ticks per second across a 90-minute run — 54,000 ticks — even 50,000
individuals means billions of updates. The obvious fix is to cap the population at a few
hundred, and that quietly breaks the ecology: small populations go extinct from sheer
demographic bad luck. The pond would collapse for reasons unrelated to anything the player
did, which is the worst available failure mode in a game about consequences.

**Trait bins** invert the representation. Rather than a list of individuals, keep a
histogram: twelve buckets by body size, each holding a population density. Each tick asks,
per bucket — how much did it eat, how much did it reproduce, how much died?

Selection then falls out for free. If fish feed preferentially from the large-size buckets,
those buckets shrink relative to the small ones and the population's mean body size drops.
This isn't a simulation of evolution; it *is* evolution, in the same form population
genetics has modelled it for a century.

The cost is roughly twelve numbers and fifty arithmetic operations per tick, against a
hundred thousand object updates. About four orders of magnitude cheaper.

**What's given up:** individual stories and spatial behaviour — but only *in the
simulation*. The renderer still draws particles that swim, school, and drift; it simply
reads population counts to decide how many to draw. No one watching a pond can count four
thousand daphnia, so nothing is lost visually. This decoupling is the load-bearing idea:
**the sim is a histogram, and the pond looks alive.**

**Why offspring spread is mandatory.** Without it, selection eventually crams the entire
population into a single bin and evolution stops permanently — the variation has been spent
and there's nothing left to select on. Real populations regenerate variation through
mutation and recombination, so offspring must land in neighbouring bins rather than exactly
their parent's. This is also exactly what makes the founder-bottleneck mechanic (§6.2)
work: a narrow starting spread produces a lineage that responds sluggishly to any pressure
the player applies.

### 11.2 Headless

Headless means the sim runs with no window and no rendering — numbers in, numbers out. Four
reasons:

- **Speed.** Rendering is typically the expensive part and it's pinned to 60fps. Unrendered,
  ninety minutes of pond takes under a second.
- **It's what makes the sweep possible.** Thousands of runs is only viable at that speed.
- **Tests can run in CI** without spinning up a browser.
- **It enforces clean architecture.** If the sim runs headless, the ecology is necessarily
  separate from the presentation. That's what allows the art to be redone without touching
  the biology, and what makes the slower aquarium mode a configuration change rather than a
  rewrite.

It also eliminates a specific bug class: when game logic is tied to the frame loop, the sim
runs faster on faster hardware, and the pond literally evolves at different speeds on
different machines. A fixed timestep in a headless-capable core makes that impossible.

Godot supports this natively via `godot --headless`, which runs project scripts with no
window and no GPU — the same mechanism used for dedicated servers and CI. The sweep harness
should be one long-running headless process that loops internally over the parameter grid,
not a fresh process per run, since engine boot time would otherwise dominate.

### 11.3 Deterministic seeding

Related to headless but distinct. A run that can't be reproduced can't be debugged. "The
pond collapsed around minute 40" is useless if there's no way back to that pond. With a
seed, the exact run replays and can be stepped through.

It also makes the sweep statistically meaningful. Parameter set A is compared against set B
*on the same seeds*, so any difference is attributable to the parameter rather than to
luck. Comparing across different random runs would require vastly more runs to detect the
same signal.

### 11.4 Three species, one trait, four principles

Interactions grow roughly quadratically. Three species means three relationships to tune;
eight species means twenty-eight. Tuning twenty-eight before confirming that one works is
how prototypes die.

More to the point, the prototype exists to answer one question: **is player-driven
evolution visible and satisfying?** Anything that doesn't help answer it is delaying the
answer.

The four-principle limit (§1) is about the player rather than the code. People hold maybe
three or four causal chains in mind at once. Add a fifth mechanism and every outcome has an
ambiguous cause — players stop being able to attribute effects, so they stop forming
hypotheses, and the game degrades into "random stuff happens." Legibility is a budget, and
it is much smaller than the budget for simulation complexity.
