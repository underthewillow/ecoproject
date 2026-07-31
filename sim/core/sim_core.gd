extends RefCounted

## Fixed-timestep, headless-capable sim core (§3.1). No rendering
## dependencies — safe to run under `godot --headless` for the sweep
## harness or the debug chart.
##
## Uses explicit preload for its own dependencies rather than the class_name
## global cache, since that cache is built by the editor and a pure
## `godot --headless -s ...` invocation (fresh checkout, CI) never triggers it.

const SimRNG = preload("res://sim/core/sim_rng.gd")
const SimState = preload("res://sim/core/sim_state.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const TICK_DT := 0.1

var _rng: SimRNG
var _config: SimConfig
var _state := SimState.new()

func _init(seed_value: int, config: SimConfig = null) -> void:
	_rng = SimRNG.new(seed_value)
	_config = config if config != null else SimConfig.new()
	_state.algae = _config.initial_algae
	_state.nutrients = _config.initial_nutrients
	_state.detritus = _config.initial_detritus
	_state.daphnia = _config.initial_daphnia
	_state.fish = _config.initial_fish

func step() -> void:
	_state.tick += 1
	_state.time += TICK_DT
	_step_ecology()

## Algae growth/uptake/mortality (§3.2-3.3), daphnia grazing/mortality
## (§3.3, single body size — trait bins arrive in Phase 4), and fish
## predation/starvation (§3.3, three trophic levels), all computed from
## the pre-tick state and applied together (explicit Euler) so which term
## gets evaluated first doesn't bias the result.
##
## Mass is conserved end to end except for fish maintenance, which is
## respired out of the system rather than routed to detritus (tracked in
## SimState.respired so that stays checkable): grazing moves algae into
## daphnia (assimilated) or detritus (egested); predation moves daphnia
## into fish (assimilated, ~10% per §3.3) or detritus (egested); daphnia
## and fish losses beyond that go to detritus or respiration respectively;
## detritus remineralises back to nutrients.
func _step_ecology() -> void:
	var c := _config
	var s := _state

	var light_term := c.light / (c.light + c.light_half_saturation)
	var temp_deviation := (c.temperature - c.temperature_optimum) / c.temperature_tolerance
	var temp_term := exp(-temp_deviation * temp_deviation)
	var nutrient_term := s.nutrients / (s.nutrients + c.nutrient_half_saturation)
	var density_term := 1.0 - s.algae / c.algae_carrying_capacity

	var algae_growth := c.algae_growth_rate * s.algae * nutrient_term * light_term * temp_term * density_term
	var algae_death := c.algae_mortality_rate * s.algae
	var remineralization := c.detritus_remineralization_rate * s.detritus

	var grazing := c.daphnia_ingestion_rate * s.daphnia * (s.algae / (s.algae + c.daphnia_algae_half_saturation))
	var assimilated := grazing * c.daphnia_assimilation_efficiency
	var egested := grazing - assimilated
	var daphnia_death := c.daphnia_mortality_rate * s.daphnia

	var predation := c.fish_ingestion_rate * s.fish * (s.daphnia / (s.daphnia + c.fish_daphnia_half_saturation))
	var assimilated_fish := predation * c.fish_trophic_efficiency
	var egested_fish := predation - assimilated_fish
	var maintenance_fish := c.fish_maintenance_rate * s.fish

	s.algae = maxf(s.algae + (algae_growth - algae_death - grazing) * TICK_DT, 0.0)
	s.nutrients = maxf(s.nutrients + (-algae_growth + remineralization) * TICK_DT, 0.0)
	s.detritus = maxf(s.detritus + (algae_death - remineralization + egested + daphnia_death + egested_fish) * TICK_DT, 0.0)
	s.daphnia = maxf(s.daphnia + (assimilated - daphnia_death - predation) * TICK_DT, 0.0)
	s.fish = maxf(s.fish + (assimilated_fish - maintenance_fish) * TICK_DT, 0.0)
	s.respired += maintenance_fish * TICK_DT

func snapshot() -> SimState:
	return _state.duplicate_state()
