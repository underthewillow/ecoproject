extends SceneTree

## Phase 3 acceptance check (§8): confirms the sweep's chosen fish combo
## lets all three trophic levels persist a full ~90 sim-minute session
## (54,000 ticks) without collapse, across seeds.
##   godot --headless --path . -s res://sim/harness/phase3_validate.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const TICK_COUNT := 54000
const SEED_COUNT := 20
const COLLAPSE_THRESHOLD := 0.01

func _initialize() -> void:
	var persisting_count := 0

	for seed_value in range(SEED_COUNT):
		var config := SimConfig.new()
		config.fish_ingestion_rate = 0.1
		config.fish_daphnia_half_saturation = 1.0
		config.fish_maintenance_rate = 0.005
		config.initial_fish = 0.5

		var sim := SimCore.new(seed_value, config)
		var daphnia_min := INF
		var fish_min := INF
		for i in TICK_COUNT:
			sim.step()
			var state = sim.snapshot()
			daphnia_min = minf(daphnia_min, state.daphnia)
			fish_min = minf(fish_min, state.fish)

		var final_state := sim.snapshot()
		var persisting := final_state.daphnia >= COLLAPSE_THRESHOLD and final_state.fish >= COLLAPSE_THRESHOLD
		if persisting:
			persisting_count += 1

		if seed_value == 0:
			var mass_total := final_state.algae + final_state.nutrients + final_state.detritus \
				+ final_state.daphnia + final_state.fish + final_state.respired
			var expected_total := config.initial_algae + config.initial_nutrients + config.initial_detritus \
				+ config.initial_daphnia + config.initial_fish
			print("seed=0 final: algae=%.4f nutrients=%.4f detritus=%.4f daphnia=%.4f fish=%.4f respired=%.4f" % [
				final_state.algae, final_state.nutrients, final_state.detritus,
				final_state.daphnia, final_state.fish, final_state.respired
			])
			print("mass check (incl. respired): total=%.6f expected=%.6f diff=%.8f" % [
				mass_total, expected_total, absf(mass_total - expected_total)
			])
			print("daphnia_min=%.4f fish_min=%.4f (how close to collapse it got)" % [daphnia_min, fish_min])

	print("persisting=%d/%d seeds" % [persisting_count, SEED_COUNT])
	quit()
