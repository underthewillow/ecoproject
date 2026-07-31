extends RefCounted

## Tunable constants and abiotic parameters for one sim run (§3.2, §3.3).
## Defaults here are reasonable starting points, not tuned — Phase 2's
## sweep harness (§5) is where the stable predator-prey band gets found.
## Kept as one object (rather than args on SimCore's constructor) so the
## harness can override individual values per run without touching SimCore.

# Abiotic (§3.2) — constant for the prototype until the player-facing setup
# screen (Phase 5) makes these configurable per run.
var light: float = 1.0
var temperature: float = 20.0

# Algae (§3.3)
var algae_growth_rate: float = 0.4          # r_A
var algae_carrying_capacity: float = 100.0  # K_A
var algae_mortality_rate: float = 0.05      # m_A
var nutrient_half_saturation: float = 5.0   # k_N
var light_half_saturation: float = 0.5
var temperature_optimum: float = 22.0
var temperature_tolerance: float = 10.0

# Detritus -> nutrient remineralization (§3.2)
var detritus_remineralization_rate: float = 0.02

# Initial state
var initial_algae: float = 1.0
var initial_nutrients: float = 20.0
var initial_detritus: float = 0.0
