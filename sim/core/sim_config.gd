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
