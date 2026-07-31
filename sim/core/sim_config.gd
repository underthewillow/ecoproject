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

# Daphnia (§3.3) — single body size for Phase 2; trait bins arrive in
# Phase 4 (§4). half_saturation here is the daphnia's own food-saturation
# constant, distinct from algae_carrying_capacity above.
var daphnia_ingestion_rate: float = 0.6
var daphnia_algae_half_saturation: float = 10.0
var daphnia_assimilation_efficiency: float = 0.4
var daphnia_mortality_rate: float = 0.02

# Fish (§3.3) — a scalar population, never trait-binned ("does not evolve
# in the prototype"). Unlike daphnia's flat mortality rate, fish decline is
# entirely energy-budget driven: dF = assimilated - maintenance*F, so a
# fish population shrinks ("starves") whenever intake can't cover upkeep,
# with no separate baseline death rate needed. Values below came out of
# the Phase 3 sweep (sim/harness/sweep_phase3.gd) — confirmed to persist
# 20/20 seeds over a full 54,000-tick run by phase3_validate.gd.
var fish_ingestion_rate: float = 0.1
var fish_daphnia_half_saturation: float = 1.0
var fish_trophic_efficiency: float = 0.10   # ~10% per §3.3
var fish_maintenance_rate: float = 0.005

# Initial state
var initial_algae: float = 1.0
var initial_nutrients: float = 20.0
var initial_detritus: float = 0.0
var initial_daphnia: float = 2.0
var initial_fish: float = 0.5
