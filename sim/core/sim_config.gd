extends RefCounted

## Tunable constants and abiotic parameters for one sim run (§3.2, §3.3).
## Kept as one object (rather than args on SimCore's constructor) so the
## sweep harness can override individual values per run without touching
## SimCore. Daphnia defaults below came out of the Phase 2 sweep
## (sim/harness/sweep_phase2.gd) — 20/20 seeds oscillating, confirmed
## sustained (not decaying) over a full 54,000-tick / 90-sim-minute run by
## sim/harness/phase2_validate.gd. Algae defaults are still the Phase 1
## values, unaffected by the sweep.

# Abiotic (§3.2) — constant for the prototype until the player-facing setup
# screen (Phase 5) makes these configurable per run.
var light: float = 1.0
var temperature: float = 20.0

# Algae (§3.3)
var algae_growth_rate: float = 0.4         # r_A
var algae_carrying_capacity: float = 60.0  # K_A
var algae_mortality_rate: float = 0.05     # m_A
var nutrient_half_saturation: float = 5.0  # k_N
var light_half_saturation: float = 0.5
var temperature_optimum: float = 22.0
var temperature_tolerance: float = 10.0

# Detritus -> nutrient remineralization (§3.2)
var detritus_remineralization_rate: float = 0.02

# Daphnia (§3.3) — half_saturation here is the daphnia's own
# food-saturation constant, distinct from algae_carrying_capacity above.
# ingestion_rate/assimilation_efficiency/mortality_rate are the Phase
# 2-validated per-capita base rates; Phase 4 (§4) layers size-dependence
# on top of them (below) rather than replacing them, so a bin at
# daphnia_reference_size behaves like the old Phase 2 scalar model did.
var daphnia_ingestion_rate: float = 0.6
var daphnia_algae_half_saturation: float = 10.0
var daphnia_assimilation_efficiency: float = 0.4
var daphnia_mortality_rate: float = 0.02

# Daphnia trait bins (§4.1/§4.2) — the three exponents below came out of
# the Phase 4 sweep (sim/harness/sweep_phase4.gd): 47/48 grid combos
# persisted without collapsing or blowing up, and the effect was robust
# rather than a narrow peak - many combos across the grid produced a
# size gap over 1.0 (out of the 1.5-wide size range) between the
# with-fish and without-fish final mean sizes. This combo sits centrally
# within the grid rather than at its boundary (size_gap=1.117 at seed 0
# over the 15,000-tick exploration window), for margin against being an
# edge-of-grid artifact. Confirmed across seeds and the full 54,000-tick
# duration by sim/harness/phase4_validate.gd.
#
# §4.2's tradeoff needs per-unit-biomass clearance efficiency to
# INCREASE with size, but §3.3's own metabolic scaling (ingestion ~
# size^0.75, sublinear) would make per-biomass efficiency DECREASE with
# size if taken alone (dividing an already-sublinear ingestion term by
# size again flips the sign of the exponent). §4.2 explicitly frames
# itself as a correction/refinement of an earlier assumption, so
# daphnia_clearance_size_exponent below is treated as the authoritative,
# game-tuned relationship (superseding the raw 0.75) rather than a
# second term multiplied on top of it - one knob, not two competing ones.
var daphnia_bin_count: int = 12
var daphnia_size_min: float = 0.5
var daphnia_size_max: float = 2.0
var daphnia_reference_size: float = 1.0
var daphnia_clearance_size_exponent: float = 1.3    # >1: larger = more efficient per unit biomass (§4.2)

# "Offspring cost scales with size, so small individuals produce more
# young" (§3.3) — implemented as assimilation EFFICIENCY decreasing with
# size (clamped to [0,1]) rather than as a divisor on offspring count.
# Efficiency is a bounded split of an already-known input (grazing ->
# assimilated + egested), so this can't create or destroy mass no matter
# the exponent; a cost multiplier on offspring count directly could, if
# it ever pushed the count above what the assimilated biomass "paid for."
var daphnia_offspring_cost_exponent: float = 1.0    # >0: larger size -> lower assimilation efficiency -> fewer offspring per unit grazed
var daphnia_spread_kernel: Array[float] = [0.6, 0.18, 0.02]  # must satisfy kernel[0] + 2*sum(kernel[1:]) == 1.0

# Initial daphnia founder distribution (§6.2) - a wide spread now; Phase
# 5's founder-size mechanic will let the player choose this per
# introduction (narrow = little variation to select on, wide = adapts
# readily).
var initial_daphnia: float = 2.0
var initial_daphnia_mean_size: float = 1.0
var initial_daphnia_size_spread: float = 0.4  # fraction of the full size range

# Fish (§3.3) — a scalar population, never trait-binned ("does not evolve
# in the prototype"). Unlike daphnia's flat mortality rate, fish decline is
# entirely energy-budget driven: dF = assimilated - maintenance*F, so a
# fish population shrinks ("starves") whenever intake can't cover upkeep,
# with no separate baseline death rate needed. Values below came out of
# the Phase 3 sweep (sim/harness/sweep_phase3.gd) — confirmed to persist
# 20/20 seeds over a full 54,000-tick run by phase3_validate.gd, prior to
# Phase 4's trait bins - expect these to need re-validating too.
var fish_ingestion_rate: float = 0.1
var fish_daphnia_half_saturation: float = 1.0
var fish_trophic_efficiency: float = 0.10   # ~10% per §3.3
var fish_maintenance_rate: float = 0.005

# Fish predation size preference (§4.2) - the size-efficiency hypothesis:
# visual planktivores preferentially eat LARGE zooplankton. Sweep-chosen
# alongside the daphnia exponents above (sweep_phase4.gd) - all three
# were searched together since they jointly determine the tradeoff.
var fish_daphnia_size_exponent: float = 1.5

# Initial state
var initial_algae: float = 1.0
var initial_nutrients: float = 20.0
var initial_detritus: float = 0.0
var initial_fish: float = 0.5

# --- Decomposer (backlog scaffold, §9's "architecture shouldn't foreclose
# this") - a detritus-eating species creating a second, two-way nutrient
# loop alongside the existing algae/daphnia/fish chain: it consumes
# detritus, splitting the intake between its own biomass and directly
# remineralized nutrients (the same assimilated/egested-style split fish
# and daphnia already use), and its own mortality returns to detritus
# rather than being respired - decomposing decomposer is still organic
# matter re-entering the pool, unlike a vertebrate's metabolic loss.
# Scalar, not trait-binned: Phase 4 already established that evolution
# stays scoped to one demonstration species (§11.4's four-principle
# legibility limit) - a second evolving population would double the
# tuning surface for a mechanic that isn't part of the shipped loop yet.
# Gated behind enable_decomposer (default off) so every existing harness
# and the current playable loop are completely unaffected; see
# sim/harness/decomposer_apex_predator_check.gd for the scaffold's own
# mass-conservation/sanity check. Values below are a plausible first
# guess, not sweep-tuned - there's no acceptance criterion for this yet
# since it isn't a build-order phase.
var enable_decomposer: bool = false
var decomposer_ingestion_rate: float = 0.3
var decomposer_detritus_half_saturation: float = 8.0
var decomposer_assimilation_efficiency: float = 0.4
var decomposer_mortality_rate: float = 0.03
var initial_decomposer: float = 0.0

# --- Apex predator (backlog scaffold) - preys on fish, closing a fourth
# trophic level. Deliberately slow (low ingestion/reproduction) by design:
# a fast-moving 4th level would double the number of oscillating
# relationships the player has to track (§11.4's quadratic-interactions
# warning); a slow one instead reads as an occasional, gentle check on
# fish rather than another fast cycle to babysit. Scalar, not trait-binned,
# same reasoning as the decomposer above. Its predation reduces fish
# directly (mirroring how fish predation reduces daphnia), assimilated
# biomass becomes apex_predator, egested biomass returns to detritus, and
# its own maintenance is respired - following fish's own pattern one level
# up. Gated behind enable_apex_predator (default off).
var enable_apex_predator: bool = false
var apex_predator_ingestion_rate: float = 0.02
var apex_predator_fish_half_saturation: float = 1.0
var apex_predator_trophic_efficiency: float = 0.10
var apex_predator_maintenance_rate: float = 0.002
var initial_apex_predator: float = 0.0

# --- Difficulty / pacing --------------------------------------------------
# A single time-dilation multiplier applied uniformly to every ecological
# rate - see sim_core.gd's _step_ecology and _step_daphnia_bins, which both
# compute `TICK_DT * pace_scale` in place of the bare TICK_DT constant
# wherever a flow actually gets applied to state. Scaling every rate by the
# same factor is a pure similarity transform: the same oscillations, the
# same collapses, the same trait-evolution curves happen, just stretched
# out in time - so a non-default pace_scale needs no re-tuning or
# re-validation against the Phase 2-4 sweeps, only more real-world session
# length to cover the same story arc. Introduction/nutrient costs are
# untouched by this (they're one-time spends against capacity, not
# per-tick rates).
#
# Defaults to Difficulty.CHALLENGING (pace_scale = 1.0) so every existing
# harness is completely unaffected. Direct playtesting found the default
# pace outrunning reaction time, hence Difficulty.CASUAL as a slower
# preset; CASUAL itself then played well enough to want something slower
# still, hence Difficulty.RELAXING - see sim/harness/phase5_validate.gd,
# which checks the naive playthrough still reaches and survives Act 3
# under all three presets.
enum Difficulty { CHALLENGING, CASUAL, RELAXING }
const PACE_SCALE_BY_DIFFICULTY := {
	Difficulty.CHALLENGING: 1.0,
	Difficulty.CASUAL: 0.5,
	Difficulty.RELAXING: 0.25,
}
var pace_scale: float = 1.0

func set_difficulty(difficulty: Difficulty) -> void:
	pace_scale = PACE_SCALE_BY_DIFFICULTY[difficulty]

# --- Phase 5: player layer (§6) -----------------------------------------
# One resource - "capacity," the pond's own life-support capacity, not an
# abstract currency (§6.3) - funds introductions and nutrients. It doesn't
# just accumulate with raw biomass: regen scales with biomass MULTIPLIED by
# how many trophic levels are currently coexisting above
# capacity_presence_floor (see sim_core.gd's _step_ecology) - a pond that's
# only ever had algae earns at the base rate, one with algae+daphnia earns
# at 2x, a full algae+daphnia+fish web at 3x. That's the actual feedback
# loop: the more balanced the pond currently is, the faster it can afford
# the next intervention, rather than a lone thriving species being just as
# "productive" as a genuinely balanced web. capacity_regen_rate itself was
# raised well above a first pass's value after that pass played too slow to
# feel responsive in practice - a headless check can measure "does this
# eventually work," not "does this feel snappy," so this number in
# particular is the most likely one to need another pass once there's a
# real UI to play against.
#
# Introduction cost scales super-linearly with founder count (exponent > 1)
# so "always buy the biggest founder" isn't strictly dominant - that would
# flatten §6.2's actual tradeoff (large founder = costly but adapts
# readily; small = cheap but evolves sluggishly) into "big is just better."
# Species base costs scale with trophic level so misordering (fish before
# daphnia, §6.1) also hurts economically, not just visibly. Checked by
# sim/harness/phase5_validate.gd's scripted naive playthrough (does
# introduce algae -> daphnia -> fish in order, as capacity allows, reach
# three-trophic persistence within one ~90 sim-minute session?).
var capacity_regen_rate: float = 0.025
var capacity_presence_floor: float = 0.1
var initial_capacity: float = 10.0
var introduction_cost_exponent: float = 1.15
var algae_introduction_base_cost: float = 2.0
var daphnia_introduction_base_cost: float = 5.0
var fish_introduction_base_cost: float = 10.0
var nutrient_cost_per_unit: float = 0.5

# Daphnia founder width (§6.2): "founder size determines the width of the
# initial distribution across bins" - a lerp between a narrow and a wide
# width_fraction, saturating at daphnia_founder_reference_count individuals.
var daphnia_founder_min_width: float = 0.05
var daphnia_founder_max_width: float = 0.5
var daphnia_founder_reference_count: float = 10.0

# Collapse/restart (§1 pillar 3): "no hard fail state... a collapse
# simplifies the pond and restarts succession from a hardier base." Gated
# behind enable_collapse_restart, defaulted off, so Phases 1-4's already
# sweep-validated dynamics stay completely unaffected; only Phase 5 callers
# (the debug UI, phase5_validate.gd) opt in explicitly.
#
# collapse_threshold is deliberately tiny, not "low" - Phase 2's own
# validated algae/daphnia oscillation legitimately dips into the 1e-3 range
# at its troughs without that being a collapse (confirmed by direct
# measurement: algae reached 0.0041 mid-run and recovered). What actually
# distinguishes a real "grazed to nothing" collapse from a deep-but-healthy
# trough is that algae growth is multiplicative on standing algae
# (algae_growth_rate * algae * ...) - once algae is floored to exactly 0.0
# by _step_ecology's maxf(...,0.0), growth is 0 forever and it can never
# recover on its own, whereas any nonzero trough, however small, still has
# a nonzero growth term and can climb back. So "at or below this threshold"
# is meant to mean "actually pinned at the zero fixed point," not merely
# "a low point in the cycle" - a much smaller number than the 0.01 a first
# pass used, which turned out to fire on ordinary troughs instead.
var enable_collapse_restart: bool = false
var collapse_threshold: float = 1e-6
var restart_algae_seed: float = 1.0
