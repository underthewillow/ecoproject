extends SceneTree

## Phase 1 acceptance check (§8): algae must reach a stable equilibrium and
## stay there. Run headless, no scene file needed:
##   godot --headless --path . -s res://sim/harness/equilibrium_check.gd -- --seed=42 --ticks=20000

const SimCore = preload("res://sim/core/sim_core.gd")

const DEFAULT_SEED := 12345
const DEFAULT_TICKS := 20000
const SAMPLE_WINDOW := 500
const STABILITY_EPSILON := 0.01

func _initialize() -> void:
	var seed_value := _arg_int("--seed=", DEFAULT_SEED)
	var tick_count := _arg_int("--ticks=", DEFAULT_TICKS)

	var sim := SimCore.new(seed_value)
	var earlier_algae := 0.0
	for i in tick_count:
		sim.step()
		if i == tick_count - SAMPLE_WINDOW:
			earlier_algae = sim.snapshot().algae

	var final_state := sim.snapshot()
	var delta := absf(final_state.algae - earlier_algae)
	var stable := delta < STABILITY_EPSILON

	print("seed=%d tick=%d algae=%.6f nutrients=%.6f detritus=%.6f delta_over_%d_ticks=%.6f stable=%s" % [
		seed_value, final_state.tick, final_state.algae, final_state.nutrients, final_state.detritus,
		SAMPLE_WINDOW, delta, stable
	])
	quit()

func _arg_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return default_value
