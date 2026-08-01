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

## Guards collapse/restart detection against the empty pre-introduction
## start (algae=0, Phase 5) itself reading as a "collapse" - see
## _check_collapse_restart(). Becomes true once algae first rises above
## collapse_threshold, i.e. once succession has actually begun.
var _pond_established: bool = false

func _init(seed_value: int, config: SimConfig = null) -> void:
	_rng = SimRNG.new(seed_value)
	_config = config if config != null else SimConfig.new()
	_state.algae = _config.initial_algae
	_state.nutrients = _config.initial_nutrients
	_state.detritus = _config.initial_detritus
	_state.fish = _config.initial_fish
	_state.capacity = _config.initial_capacity
	_pond_established = _state.algae >= _config.collapse_threshold

	_daphnia = TraitBinPopulation.new(_config.daphnia_bin_count, _config.daphnia_size_min, _config.daphnia_size_max, _config.daphnia_spread_kernel)
	_daphnia.seed_population(_config.initial_daphnia, _config.initial_daphnia_mean_size, _config.initial_daphnia_size_spread)
	_sync_daphnia_snapshot()

func step() -> void:
	_state.tick += 1
	_state.time += TICK_DT
	_step_ecology()

## Directly sets the fish population - a controlled external mutation, in
## the same spirit as introduce_species() below but bypassing cost/capacity.
## Not called anywhere in the ecology step itself; currently only used by
## phase4_validate.gd to test §4.2's literal claim ("remove the pressure and
## it climbs back") as a single dynamic run rather than only as two
## separate static ones.
func set_fish(value: float) -> void:
	_state.fish = maxf(value, 0.0)

## Time-dilation difficulty lever (see sim_config.gd's "Difficulty / pacing"
## section) - live-settable so the debug UI can A/B the two presets within
## one session rather than needing a restart. Clamped away from zero/negative
## since that would freeze or invert the ecology rather than merely slow it.
func set_pace_scale(value: float) -> void:
	_config.pace_scale = maxf(value, 0.0001)

func get_pace_scale() -> float:
	return _config.pace_scale

## Player mechanics (§6). Two verbs: introduce a species (§6.1/§6.2) and add
## nutrients (§6.4) - both spend capacity, both no-ops (return false, no
## partial charge) if unaffordable or invalid, so a caller never needs to
## pre-check affordability itself.
func get_introduction_cost(species: String, founder_count: float) -> float:
	var base := _introduction_base_cost(species)
	if base < 0.0:
		return -1.0
	return base * pow(maxf(founder_count, 0.0), _config.introduction_cost_exponent)

func _introduction_base_cost(species: String) -> float:
	match species:
		"algae":
			return _config.algae_introduction_base_cost
		"daphnia":
			return _config.daphnia_introduction_base_cost
		"fish":
			return _config.fish_introduction_base_cost
		_:
			return -1.0

func introduce_species(species: String, founder_count: float) -> bool:
	if founder_count <= 0.0:
		return false
	var cost := get_introduction_cost(species, founder_count)
	if cost < 0.0 or _state.capacity < cost:
		return false

	match species:
		"algae":
			_state.algae += founder_count
		"daphnia":
			_daphnia.add_population(founder_count, _config.daphnia_reference_size, _daphnia_founder_width(founder_count))
		"fish":
			_state.fish += founder_count

	_state.capacity -= cost
	_sync_daphnia_snapshot()
	return true

func _daphnia_founder_width(founder_count: float) -> float:
	var c := _config
	var t := clampf(founder_count / c.daphnia_founder_reference_count, 0.0, 1.0)
	return lerpf(c.daphnia_founder_min_width, c.daphnia_founder_max_width, t)

func add_nutrients(amount: float) -> bool:
	if amount <= 0.0:
		return false
	var cost := amount * _config.nutrient_cost_per_unit
	if _state.capacity < cost:
		return false
	_state.nutrients += amount
	_state.capacity -= cost
	return true

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
	# Every flow below is applied via `dt`, not the bare TICK_DT constant -
	# this is the whole of the time-dilation difficulty lever (sim_config.gd's
	# pace_scale): uniformly stretching how much ecological change happens
	# per tick, without touching any of the tuned per-second rate constants.
	var dt := TICK_DT * c.pace_scale

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

	s.algae = maxf(s.algae + (algae_growth - algae_death - total_grazing) * dt, 0.0)
	s.nutrients = maxf(s.nutrients + (-algae_growth + remineralization) * dt, 0.0)
	s.detritus = maxf(s.detritus + (algae_death - remineralization + total_egested + total_baseline_death + egested_fish) * dt, 0.0)
	s.fish = maxf(s.fish + (assimilated_fish - maintenance_fish) * dt, 0.0)
	s.respired += maintenance_fish * dt

	var daphnia_total := _daphnia.total_population()
	var living_biomass := s.algae + daphnia_total + s.fish
	var trophic_diversity := _trophic_diversity(s.algae, daphnia_total, s.fish)
	s.capacity += c.capacity_regen_rate * living_biomass * trophic_diversity * dt

	_check_collapse_restart()
	_sync_daphnia_snapshot()

## How many of {algae, daphnia, fish} are currently meaningfully present
## (§6.3's "the more balanced, the more capacity" feedback loop) - 0 to 3,
## multiplying capacity regen directly rather than biomass alone. A pond
## that's only ever grown algae still earns capacity at the base rate (so
## the very first introduction can always bootstrap the next one); one
## where algae and daphnia coexist earns at 2x; a full three-level web at
## 3x. This rewards a currently-functioning food web over a single species
## sitting at high biomass, without needing any rolling-window history -
## it's read straight off this tick's populations.
func _trophic_diversity(algae: float, daphnia_total: float, fish: float) -> float:
	var floor_value := _config.capacity_presence_floor
	var count := 0
	if algae >= floor_value:
		count += 1
	if daphnia_total >= floor_value:
		count += 1
	if fish >= floor_value:
		count += 1
	return float(count)

## "No hard fail state... a collapse simplifies the pond and restarts
## succession from a hardier base" (§1 pillar 3), triggered by algae
## crashing to nothing - "daphnia with no predator for too long... crash
## the pond from the bottom" (§6.1) is the literal scenario. Nutrients,
## detritus, and capacity are left untouched: the escalating nutrient/
## detritus load (§2) is the intended difficulty curve, so a restarted pond
## should be harder than the original bare-water start, not reset alongside
## it. Off by default (enable_collapse_restart) - see sim_config.gd.
func _check_collapse_restart() -> void:
	if not _config.enable_collapse_restart:
		return
	if _state.algae >= _config.collapse_threshold:
		_pond_established = true
		return
	if not _pond_established:
		return

	_state.algae = _config.restart_algae_seed
	_state.fish = 0.0
	_daphnia.densities.fill(0.0)
	_state.collapse_count += 1
	_pond_established = false

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
	var dt := TICK_DT * c.pace_scale
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
		offspring[i] = assimilated * dt
		vulnerable_biomass[i] = vis
		net_survival_delta[i] = -baseline_death * dt  # predation subtracted below, once the pooled total is known

	var total_predation := 0.0
	if vulnerable_total > 0.0:
		total_predation = c.fish_ingestion_rate * fish * (vulnerable_total / (vulnerable_total + c.fish_daphnia_half_saturation))
		for i in bin_count:
			if vulnerable_biomass[i] <= 0.0:
				continue
			var predation_i: float = total_predation * (vulnerable_biomass[i] / vulnerable_total)
			net_survival_delta[i] -= predation_i * dt

	_daphnia.apply_tick(net_survival_delta, offspring)

	return {
		"total_grazing": total_grazing,
		"total_egested": total_egested,
		"total_baseline_death": total_baseline_death,
		"total_predation": total_predation,
	}

func snapshot() -> SimState:
	return _state.duplicate_state()
