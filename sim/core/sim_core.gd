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

func step() -> void:
	_state.tick += 1
	_state.time += TICK_DT
	_step_algae()

## Algae growth, nutrient uptake, carrying capacity, death to detritus,
## and detritus remineralization back to nutrients (§3.2, §3.3). Total
## algae + nutrients + detritus mass is conserved by construction — growth
## moves N into A, death moves A into D, remineralization moves D into N —
## which is what lets this settle into a stable equilibrium instead of
## draining nutrients to zero.
func _step_algae() -> void:
	var c := _config
	var s := _state

	var light_term := c.light / (c.light + c.light_half_saturation)
	var temp_deviation := (c.temperature - c.temperature_optimum) / c.temperature_tolerance
	var temp_term := exp(-temp_deviation * temp_deviation)
	var nutrient_term := s.nutrients / (s.nutrients + c.nutrient_half_saturation)
	var density_term := 1.0 - s.algae / c.algae_carrying_capacity

	var growth := c.algae_growth_rate * s.algae * nutrient_term * light_term * temp_term * density_term
	var death := c.algae_mortality_rate * s.algae
	var remineralization := c.detritus_remineralization_rate * s.detritus

	s.algae = maxf(s.algae + (growth - death) * TICK_DT, 0.0)
	s.nutrients = maxf(s.nutrients + (-growth + remineralization) * TICK_DT, 0.0)
	s.detritus = maxf(s.detritus + (death - remineralization) * TICK_DT, 0.0)

func snapshot() -> SimState:
	return _state.duplicate_state()
