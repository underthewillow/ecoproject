extends SceneTree

## Phase 0 acceptance check (§8): same seed must produce identical output
## every time. Run headless, no scene file needed:
##   godot --headless --path . -s res://sim/harness/determinism_check.gd -- --seed=42 --ticks=1000
##
## Uses explicit preload rather than the class_name global cache, since that
## cache is built by the editor and won't exist on a fresh checkout or CI
## runner that never opens the editor.

const SimCore = preload("res://sim/core/sim_core.gd")

const DEFAULT_SEED := 12345
const DEFAULT_TICKS := 1000

func _initialize() -> void:
	var seed_value := _arg_int("--seed=", DEFAULT_SEED)
	var tick_count := _arg_int("--ticks=", DEFAULT_TICKS)

	var sim := SimCore.new(seed_value)
	for i in tick_count:
		sim.step()
	var final_state := sim.snapshot()

	print("seed=%d tick=%d time=%.4f algae=%.10f nutrients=%.10f detritus=%.10f daphnia=%.10f fish=%.10f" % [
		seed_value, final_state.tick, final_state.time,
		final_state.algae, final_state.nutrients, final_state.detritus, final_state.daphnia, final_state.fish
	])
	quit()

func _arg_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return default_value
