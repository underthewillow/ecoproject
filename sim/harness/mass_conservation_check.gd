extends SceneTree

## Mass-conservation regression check (§3.1's "no term biases the
## result" + the respired-field accounting described throughout
## sim_core.gd). algae + nutrients + detritus + daphnia + fish + respired
## should stay exactly constant (up to floating point drift) for the
## entire run, tick by tick - every flow in the ecology either moves mass
## between these pools or explicitly respires it, never creates or
## destroys it. Written alongside Phase 4's trait-bin rework (§4), which
## introduced meaningfully more complex per-bin math (grazing split by
## assimilation efficiency, offspring redistributed across bins with
## boundary reflection) - exactly the kind of change where a mass leak is
## easy to introduce and easy to miss without a dedicated check. Kept as
## a permanent harness, not a one-off, since any future change to the
## ecology equations should be re-verified against this.
##
## Run headless:
##   godot --headless --path . -s res://sim/harness/mass_conservation_check.gd -- --seed=42 --ticks=54000

const SimCore = preload("res://sim/core/sim_core.gd")

const DEFAULT_SEED := 42
const DEFAULT_TICKS := 54000
const TOLERANCE := 1e-6

func _initialize() -> void:
	var seed_value := _arg_int("--seed=", DEFAULT_SEED)
	var tick_count := _arg_int("--ticks=", DEFAULT_TICKS)

	var sim := SimCore.new(seed_value)
	var initial := sim.snapshot()
	var initial_total := _total_mass(initial)

	var max_drift := 0.0
	var max_drift_tick := 0
	for i in tick_count:
		sim.step()
		var s := sim.snapshot()
		var drift := absf(_total_mass(s) - initial_total)
		if drift > max_drift:
			max_drift = drift
			max_drift_tick = s.tick

	var final := sim.snapshot()
	var final_total := _total_mass(final)
	var conserved := max_drift < TOLERANCE

	print("seed=%d ticks=%d initial_total=%.10f final_total=%.10f max_drift=%.10f at_tick=%d conserved=%s" % [
		seed_value, tick_count, initial_total, final_total, max_drift, max_drift_tick, conserved
	])
	quit(0 if conserved else 1)

func _total_mass(s) -> float:
	return s.algae + s.nutrients + s.detritus + s.daphnia + s.fish + s.respired

func _arg_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return int(arg.substr(prefix.length()))
	return default_value
