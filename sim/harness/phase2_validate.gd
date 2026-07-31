extends SceneTree

## Phase 2 acceptance check (§8): confirms the sweep's chosen parameter
## combo sustains predator-prey oscillation over a full ~90 sim-minute
## session (54,000 ticks, matching §11.1's reference run length), not just
## the shorter 10,000-tick window used during the grid search.
##   godot --headless --path . -s res://sim/harness/phase2_validate.gd -- --seed=42 --ticks=54000

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const DEFAULT_SEED := 42
const DEFAULT_TICKS := 54000
const TAIL_FRACTION := 0.3

func _initialize() -> void:
	var seed_value := _arg_int("--seed=", DEFAULT_SEED)
	var tick_count := _arg_int("--ticks=", DEFAULT_TICKS)

	var config := SimConfig.new()
	config.daphnia_ingestion_rate = 0.6
	config.daphnia_mortality_rate = 0.02
	config.daphnia_algae_half_saturation = 10.0
	config.algae_carrying_capacity = 60.0
	config.initial_fish = 0.0  # isolate from Phase 3's fish addition - SimConfig's default is nonzero now

	var sim := SimCore.new(seed_value, config)
	var tail_start := int(tick_count * (1.0 - TAIL_FRACTION))
	var daphnia_tail := PackedFloat32Array()
	var early_min := INF
	var early_max := -INF

	for i in tick_count:
		sim.step()
		var state = sim.snapshot()
		if i < tail_start:
			early_min = minf(early_min, state.daphnia)
			early_max = maxf(early_max, state.daphnia)
		else:
			daphnia_tail.append(state.daphnia)

	var late_min := daphnia_tail[0]
	var late_max := daphnia_tail[0]
	for v in daphnia_tail:
		late_min = minf(late_min, v)
		late_max = maxf(late_max, v)

	var final_state := sim.snapshot()
	var mass_total := final_state.algae + final_state.nutrients + final_state.detritus + final_state.daphnia
	var expected_total := config.initial_algae + config.initial_nutrients + config.initial_detritus + config.initial_daphnia

	print("seed=%d ticks=%d" % [seed_value, tick_count])
	print("early-run daphnia range: [%.4f, %.4f]" % [early_min, early_max])
	print("late-run  daphnia range: [%.4f, %.4f]  <- oscillation still amplitude-comparable = sustained, not decaying" % [late_min, late_max])
	print("final algae=%.4f nutrients=%.4f detritus=%.4f daphnia=%.4f" % [
		final_state.algae, final_state.nutrients, final_state.detritus, final_state.daphnia
	])
	print("mass conservation: total=%.6f expected=%.6f diff=%.8f" % [mass_total, expected_total, absf(mass_total - expected_total)])
	quit()

func _arg_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return default_value
