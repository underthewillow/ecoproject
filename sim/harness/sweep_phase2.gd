extends SceneTree

## Phase 2 sweep (§5): grid-search daphnia/algae parameters across seeds to
## find a regime with sustained predator-prey oscillation that neither
## collapses (daphnia extinction) nor flatlines (settles to a fixed point)
## nor blows up. Writes one CSV row per (parameter combo, seed) run to
## sweep_results/phase2_sweep.csv (gitignored — regenerate, don't commit).
##
## Run: godot --headless --path . -s res://sim/harness/sweep_phase2.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const TICKS_PER_RUN := 10000
const SEED_COUNT := 20
const TAIL_FRACTION := 0.3
const FLATLINE_CV_THRESHOLD := 0.02
const COLLAPSE_THRESHOLD := 0.01
const BLOWUP_THRESHOLD := 1.0e6

const INGESTION_RATES := [0.3, 0.6, 1.0]
const MORTALITY_RATES := [0.02, 0.05, 0.1]
const HALF_SATURATIONS := [10.0, 20.0, 40.0]
const CARRYING_CAPACITIES := [60.0, 100.0, 150.0]

func _initialize() -> void:
	var output_dir := ProjectSettings.globalize_path("res://sweep_results")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file := FileAccess.open(output_dir + "/phase2_sweep.csv", FileAccess.WRITE)
	file.store_line("ingestion_rate,mortality_rate,half_saturation,carrying_capacity,seed,outcome,daphnia_min,daphnia_max,daphnia_mean,daphnia_cv,algae_min,algae_max,period_estimate")

	var run_count := 0
	var best_combo := {}
	var best_oscillating_seeds := -1

	for ingestion in INGESTION_RATES:
		for mortality in MORTALITY_RATES:
			for half_sat in HALF_SATURATIONS:
				for capacity in CARRYING_CAPACITIES:
					var combo_oscillating := 0
					for seed_value in range(SEED_COUNT):
						var config := SimConfig.new()
						config.initial_fish = 0.0  # isolate from Phase 3's fish addition - SimConfig's default is nonzero now
						config.daphnia_ingestion_rate = ingestion
						config.daphnia_mortality_rate = mortality
						config.daphnia_algae_half_saturation = half_sat
						config.algae_carrying_capacity = capacity

						var result := _run_one(seed_value, config)
						run_count += 1
						if result.outcome == "oscillating":
							combo_oscillating += 1

						file.store_line("%.3f,%.3f,%.3f,%.3f,%d,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.4f" % [
							ingestion, mortality, half_sat, capacity, seed_value, result.outcome,
							result.daphnia_min, result.daphnia_max, result.daphnia_mean, result.daphnia_cv,
							result.algae_min, result.algae_max, result.period_estimate
						])

					if combo_oscillating > best_oscillating_seeds:
						best_oscillating_seeds = combo_oscillating
						best_combo = {
							"ingestion_rate": ingestion, "mortality_rate": mortality,
							"half_saturation": half_sat, "carrying_capacity": capacity,
						}

	file.close()
	print("runs=%d" % run_count)
	print("best combo: %s (%d/%d seeds oscillating)" % [best_combo, best_oscillating_seeds, SEED_COUNT])
	quit()

func _run_one(seed_value: int, config: SimConfig) -> Dictionary:
	var sim := SimCore.new(seed_value, config)
	var tail_start := int(TICKS_PER_RUN * (1.0 - TAIL_FRACTION))
	var daphnia_tail := PackedFloat32Array()
	var algae_tail := PackedFloat32Array()
	var blew_up := false

	for i in TICKS_PER_RUN:
		sim.step()
		if i >= tail_start:
			var state = sim.snapshot()
			if not is_finite(state.daphnia) or not is_finite(state.algae) \
					or state.daphnia > BLOWUP_THRESHOLD or state.algae > BLOWUP_THRESHOLD:
				blew_up = true
			daphnia_tail.append(state.daphnia)
			algae_tail.append(state.algae)

	var daphnia_min := daphnia_tail[0]
	var daphnia_max := daphnia_tail[0]
	var daphnia_sum := 0.0
	for v in daphnia_tail:
		daphnia_min = minf(daphnia_min, v)
		daphnia_max = maxf(daphnia_max, v)
		daphnia_sum += v
	var daphnia_mean := daphnia_sum / daphnia_tail.size()

	var variance_sum := 0.0
	for v in daphnia_tail:
		variance_sum += (v - daphnia_mean) * (v - daphnia_mean)
	var daphnia_stddev := sqrt(variance_sum / daphnia_tail.size())
	var daphnia_cv := (daphnia_stddev / daphnia_mean) if daphnia_mean > 0.0001 else 0.0

	var algae_min := algae_tail[0]
	var algae_max := algae_tail[0]
	for v in algae_tail:
		algae_min = minf(algae_min, v)
		algae_max = maxf(algae_max, v)

	var peak_count := 0
	for i in range(1, daphnia_tail.size() - 1):
		if daphnia_tail[i] > daphnia_tail[i - 1] and daphnia_tail[i] > daphnia_tail[i + 1]:
			peak_count += 1
	var tail_sim_time := daphnia_tail.size() * SimCore.TICK_DT
	var period_estimate := (tail_sim_time / peak_count) if peak_count > 0 else 0.0

	var outcome := "oscillating"
	if blew_up:
		outcome = "blew_up"
	elif daphnia_mean < COLLAPSE_THRESHOLD:
		outcome = "collapsed"
	elif daphnia_cv < FLATLINE_CV_THRESHOLD:
		outcome = "flatlined"

	return {
		"outcome": outcome,
		"daphnia_min": daphnia_min, "daphnia_max": daphnia_max,
		"daphnia_mean": daphnia_mean, "daphnia_cv": daphnia_cv,
		"algae_min": algae_min, "algae_max": algae_max,
		"period_estimate": period_estimate,
	}
