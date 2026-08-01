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
const TraitBinPopulation = preload("res://sim/core/trait_bin_population.gd")

const TICK_DT := 0.1

var _rng: SimRNG
var _config: SimConfig
var _state := SimState.new()
var _daphnia: TraitBinPopulation

func _init(seed_value: int, config: SimConfig = null) -> void:
	_rng = SimRNG.new(seed_value)
	_config = config if config != null else SimConfig.new()
	_state.algae = _config.initial_algae
	_state.nutrients = _config.initial_nutrients
	_state.detritus = _config.initial_detritus
	_state.fish = _config.initial_fish

	_daphnia = TraitBinPopulation.new(_config.daphnia_bin_count, _config.daphnia_size_min, _config.daphnia_size_max, _config.daphnia_spread_kernel)
	_daphnia.seed_population(_config.initial_daphnia, _config.initial_daphnia_mean_size, _config.initial_daphnia_size_spread)
	_sync_daphnia_snapshot()

func step() -> void:
	_state.tick += 1
	_state.time += TICK_DT
	_step_ecology()

## Directly sets the fish population - a controlled external mutation,
## the same shape of interface Phase 5's player-driven introduce/remove
## actions will eventually need (§6.1). Not called anywhere in the
## ecology step itself; currently only used by phase4_validate.gd to
## test §4.2's literal claim ("remove the pressure and it climbs back")
## as a single dynamic run rather than only as two separate static ones.
func set_fish(value: float) -> void:
	_state.fish = maxf(value, 0.0)

func _sync_daphnia_snapshot() -> void:
	_state.daphnia = _daphnia.total_population()
	_state.daphnia_mean_size = _daphnia.mean_trait()
	_state.daphnia_bins = _daphnia.densities.duplicate()

## Algae growth/uptake/mortality (§3.2-3.3), daphnia grazing/mortality
## (§3.3/§4, now size-binned — see below), and fish predation/starvation
## (§3.3, three trophic levels), all computed from the pre-tick state and
## applied together (explicit Euler) so which term gets evaluated first
## doesn't bias the result.
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

	var daphnia_result := _step_daphnia_bins(s.algae, s.fish)
	var total_grazing: float = daphnia_result.total_grazing
	var total_egested: float = daphnia_result.total_egested
	var total_baseline_death: float = daphnia_result.total_baseline_death
	var total_predation: float = daphnia_result.total_predation

	var assimilated_fish := total_predation * c.fish_trophic_efficiency
	var egested_fish := total_predation - assimilated_fish
	var maintenance_fish := c.fish_maintenance_rate * s.fish

	s.algae = maxf(s.algae + (algae_growth - algae_death - total_grazing) * TICK_DT, 0.0)
	s.nutrients = maxf(s.nutrients + (-algae_growth + remineralization) * TICK_DT, 0.0)
	s.detritus = maxf(s.detritus + (algae_death - remineralization + total_egested + total_baseline_death + egested_fish) * TICK_DT, 0.0)
	s.fish = maxf(s.fish + (assimilated_fish - maintenance_fish) * TICK_DT, 0.0)
	s.respired += maintenance_fish * TICK_DT

	_sync_daphnia_snapshot()

## Per-bin daphnia ecology (§4). Two size-dependent relationships
## implement §4.2's tradeoff:
## - Grazing (algal clearance) efficiency per unit biomass INCREASES with
##   size - large daphnia are the better competitors when unpredated.
## - Fish predation preference INCREASES with size (visual planktivores
##   preferentially eat large zooplankton - Brooks & Dodson 1965) -
##   computed via a pooled "vulnerable biomass" across all bins so fish
##   have one shared, saturating total appetite (matching the original
##   Phase 3 functional response) that gets split between bins by
##   relative visibility, rather than each bin saturating independently
##   against its own tiny population.
## Existing individuals in a bin only ever leave (death, predation) -
## they don't change size. All population GAIN happens through
## reproduction (offspring, redistributed to neighbouring bins via the
## spread kernel - see TraitBinPopulation), which is what makes this an
## evolutionary model rather than a set of independent per-bin logistic
## growth curves.
func _step_daphnia_bins(algae: float, fish: float) -> Dictionary:
	var c := _config
	var bin_count := _daphnia.bin_count

	var net_survival_delta: Array[float] = []
	var offspring: Array[float] = []
	var vulnerable_biomass: Array[float] = []
	net_survival_delta.resize(bin_count)
	offspring.resize(bin_count)
	vulnerable_biomass.resize(bin_count)

	var total_grazing := 0.0
	var total_egested := 0.0
	var total_baseline_death := 0.0
	var vulnerable_total := 0.0

	for i in bin_count:
		var density: float = _daphnia.densities[i]
		if density <= 0.0:
			net_survival_delta[i] = 0.0
			offspring[i] = 0.0
			vulnerable_biomass[i] = 0.0
			continue

		var size_ratio: float = _daphnia.bin_trait_value(i) / c.daphnia_reference_size

		var clearance_mult := pow(size_ratio, c.daphnia_clearance_size_exponent)
		var grazing: float = c.daphnia_ingestion_rate * clearance_mult * density * (algae / (algae + c.daphnia_algae_half_saturation))

		# Assimilation efficiency decreasing with size is how "offspring
		# cost scales with size" (§3.3) is implemented - a bounded split
		# of grazing into assimilated/egested, so it can't create or
		# destroy mass regardless of the exponent (see sim_config.gd).
		var efficiency := clampf(c.daphnia_assimilation_efficiency * pow(size_ratio, -c.daphnia_offspring_cost_exponent), 0.0, 1.0)
		var assimilated := grazing * efficiency
		var egested := grazing - assimilated

		var baseline_death: float = c.daphnia_mortality_rate * density
		var vis: float = density * pow(size_ratio, c.fish_daphnia_size_exponent)

		total_grazing += grazing
		total_egested += egested
		total_baseline_death += baseline_death
		vulnerable_total += vis

		# offspring = assimilated exactly (mass-conserving: all assimilated
		# biomass becomes new population, redistributed by size via the
		# spread kernel in apply_tick, not lost or multiplied here).
		offspring[i] = assimilated * TICK_DT
		vulnerable_biomass[i] = vis
		net_survival_delta[i] = -baseline_death * TICK_DT  # predation subtracted below, once the pooled total is known

	var total_predation := 0.0
	if vulnerable_total > 0.0:
		total_predation = c.fish_ingestion_rate * fish * (vulnerable_total / (vulnerable_total + c.fish_daphnia_half_saturation))
		for i in bin_count:
			if vulnerable_biomass[i] <= 0.0:
				continue
			var predation_i: float = total_predation * (vulnerable_biomass[i] / vulnerable_total)
			net_survival_delta[i] -= predation_i * TICK_DT

	_daphnia.apply_tick(net_survival_delta, offspring)

	return {
		"total_grazing": total_grazing,
		"total_egested": total_egested,
		"total_baseline_death": total_baseline_death,
		"total_predation": total_predation,
	}

func snapshot() -> SimState:
	return _state.duplicate_state()
