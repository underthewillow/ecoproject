extends SceneTree

## Phase 4 sweep (§5): grid-search the three new size-dependent exponents
## (algae/daphnia/fish base rates stay at their Phase 2/3-validated
## defaults) to find a regime where §4.2's tradeoff actually produces a
## measurable effect: does mean daphnia body size come out clearly larger
## without fish than with them?
##
## Structurally different from sweep_phase2.gd/sweep_phase3.gd: those
## scored a single run per combo against a collapse/blowup bar. This one
## runs TWO simulations per combo - fish present, fish absent - and
## scores combos by the GAP between their final mean daphnia sizes (in
## the expected direction: larger without fish), filtered to combos
## where both runs still persist without collapsing or blowing up.
##
## Exploration uses seed=0 only and a shorter run, same reasoning as
## sweep_phase3.gd: this sim has no stochastic terms yet, so every seed
## produces bit-identical output - the winning combo still gets a genuine
## 20-seed x full-duration confirmation afterward (phase4_validate.gd).
##
## Run: godot --headless --path . -s res://sim/harness/sweep_phase4.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const EXPLORE_TICKS := 15000
const EXPLORE_SEED := 0
const COLLAPSE_THRESHOLD := 0.01
const BLOWUP_THRESHOLD := 1.0e6
const FOUNDER_FISH := 0.5  # Phase 3-validated

const CLEARANCE_EXPONENTS := [1.0, 1.3, 1.6, 2.0]
const FISH_SIZE_EXPONENTS := [0.5, 1.0, 1.5, 2.0]
const OFFSPRING_COST_EXPONENTS := [0.0, 0.5, 1.0]

func _initialize() -> void:
	var output_dir := ProjectSettings.globalize_path("res://sweep_results")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file := FileAccess.open(output_dir + "/phase4_sweep.csv", FileAccess.WRITE)
	file.store_line("clearance_exponent,fish_size_exponent,offspring_cost_exponent,outcome_with_fish,outcome_without_fish,mean_size_with_fish,mean_size_without_fish,size_gap,daphnia_min_with_fish,fish_min")

	var run_count := 0
	var valid_count := 0
	var best_combo := {}
	var best_gap := -INF

	for clearance in CLEARANCE_EXPONENTS:
		for fish_size in FISH_SIZE_EXPONENTS:
			for offspring_cost in OFFSPRING_COST_EXPONENTS:
				var with_fish := _run_one(EXPLORE_SEED, clearance, fish_size, offspring_cost, FOUNDER_FISH, EXPLORE_TICKS)
				var without_fish := _run_one(EXPLORE_SEED, clearance, fish_size, offspring_cost, 0.0, EXPLORE_TICKS)
				run_count += 1

				var size_gap: float = without_fish.mean_size_final - with_fish.mean_size_final
				var valid: bool = with_fish.outcome == "persisting" and without_fish.outcome != "blew_up" and without_fish.daphnia_min >= COLLAPSE_THRESHOLD

				if valid:
					valid_count += 1
					if size_gap > best_gap:
						best_gap = size_gap
						best_combo = {
							"clearance_exponent": clearance, "fish_size_exponent": fish_size,
							"offspring_cost_exponent": offspring_cost,
						}

				file.store_line("%.3f,%.3f,%.3f,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f" % [
					clearance, fish_size, offspring_cost, with_fish.outcome, without_fish.outcome,
					with_fish.mean_size_final, without_fish.mean_size_final, size_gap,
					with_fish.daphnia_min, with_fish.fish_min
				])

	file.close()
	print("runs=%d (x2 per combo) valid=%d" % [run_count, valid_count])
	print("best combo: %s (size_gap=%.4f)" % [best_combo, best_gap])
	quit()

func _run_one(seed_value: int, clearance_exponent: float, fish_size_exponent: float, offspring_cost_exponent: float, founder_fish: float, tick_count: int) -> Dictionary:
	var config := SimConfig.new()
	config.daphnia_clearance_size_exponent = clearance_exponent
	config.fish_daphnia_size_exponent = fish_size_exponent
	config.daphnia_offspring_cost_exponent = offspring_cost_exponent
	config.initial_fish = founder_fish

	var sim := SimCore.new(seed_value, config)
	var daphnia_min := INF
	var fish_min := INF
	var algae_min := INF
	var blew_up := false

	for i in tick_count:
		sim.step()
		var state = sim.snapshot()
		if not is_finite(state.daphnia) or not is_finite(state.fish) or not is_finite(state.algae) \
				or state.daphnia > BLOWUP_THRESHOLD or state.fish > BLOWUP_THRESHOLD or state.algae > BLOWUP_THRESHOLD:
			blew_up = true
		daphnia_min = minf(daphnia_min, state.daphnia)
		fish_min = minf(fish_min, state.fish)
		algae_min = minf(algae_min, state.algae)

	var final_state := sim.snapshot()
	var outcome := "persisting"
	if blew_up:
		outcome = "blew_up"
	elif final_state.daphnia < COLLAPSE_THRESHOLD or (founder_fish > 0.0 and final_state.fish < COLLAPSE_THRESHOLD):
		outcome = "collapsed"

	return {
		"outcome": outcome,
		"mean_size_final": final_state.daphnia_mean_size,
		"daphnia_min": daphnia_min, "fish_min": fish_min, "algae_min": algae_min,
	}
