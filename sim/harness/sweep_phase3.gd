extends SceneTree

## Phase 3 sweep (§5): grid-search fish parameters (algae/daphnia stay at
## their Phase 2-validated defaults) to find a regime where all three
## trophic levels persist 90+ sim-minutes without collapse (§8's Phase 3
## acceptance bar).
##
## Exploration pass uses seed=0 only and a shorter run: Phase 2's sweep
## established that this sim has no stochastic terms yet (§11.1 - density
## equations, not individuals - so nothing here consumes the RNG), meaning
## every seed produces bit-identical output. Running 20 identical seeds
## per combo during a 144-combo grid search would be 20x wasted compute
## for zero information. The winning combo still gets a genuine 20-seed x
## full-duration confirmation afterward (phase3_validate.gd) so "verified
## across seeds" stays an honest claim once seeds do matter (Phase 4/5).
##
## Run: godot --headless --path . -s res://sim/harness/sweep_phase3.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const EXPLORE_TICKS := 15000
const EXPLORE_SEED := 0
const COLLAPSE_THRESHOLD := 0.01
const BLOWUP_THRESHOLD := 1.0e6

const INGESTION_RATES := [0.05, 0.1, 0.2, 0.4]
const HALF_SATURATIONS := [0.5, 1.0, 2.0]
const MAINTENANCE_RATES := [0.005, 0.01, 0.02, 0.04]
const FOUNDER_SIZES := [0.2, 0.5, 1.0]

func _initialize() -> void:
	var output_dir := ProjectSettings.globalize_path("res://sweep_results")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file := FileAccess.open(output_dir + "/phase3_sweep.csv", FileAccess.WRITE)
	file.store_line("ingestion_rate,half_saturation,maintenance_rate,founder_fish,outcome,daphnia_final,fish_final,daphnia_min,fish_min,algae_min")

	var run_count := 0
	var persisting_count := 0
	var best_combo := {}
	var best_margin := -INF  # how far the weakest population stayed above zero, as a robustness proxy

	for ingestion in INGESTION_RATES:
		for half_sat in HALF_SATURATIONS:
			for maintenance in MAINTENANCE_RATES:
				for founder in FOUNDER_SIZES:
					var config := SimConfig.new()
					config.fish_ingestion_rate = ingestion
					config.fish_daphnia_half_saturation = half_sat
					config.fish_maintenance_rate = maintenance
					config.initial_fish = founder

					var result := _run_one(EXPLORE_SEED, config, EXPLORE_TICKS)
					run_count += 1
					if result.outcome == "persisting":
						persisting_count += 1
						var margin: float = minf(result.daphnia_min, result.fish_min)
						if margin > best_margin:
							best_margin = margin
							best_combo = {
								"ingestion_rate": ingestion, "half_saturation": half_sat,
								"maintenance_rate": maintenance, "founder_fish": founder,
							}

					file.store_line("%.3f,%.3f,%.3f,%.3f,%s,%.6f,%.6f,%.6f,%.6f,%.6f" % [
						ingestion, half_sat, maintenance, founder, result.outcome,
						result.daphnia_final, result.fish_final,
						result.daphnia_min, result.fish_min, result.algae_min
					])

	file.close()
	print("runs=%d persisting=%d" % [run_count, persisting_count])
	print("best combo: %s (min population margin=%.4f)" % [best_combo, best_margin])
	quit()

func _run_one(seed_value: int, config: SimConfig, tick_count: int) -> Dictionary:
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
	elif final_state.daphnia < COLLAPSE_THRESHOLD or final_state.fish < COLLAPSE_THRESHOLD:
		outcome = "collapsed"

	return {
		"outcome": outcome,
		"daphnia_final": final_state.daphnia, "fish_final": final_state.fish,
		"daphnia_min": daphnia_min, "fish_min": fish_min, "algae_min": algae_min,
	}
