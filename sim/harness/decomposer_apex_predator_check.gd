extends SceneTree

## Backlog scaffold check (not a numbered build-order phase) for the
## detritus-eating decomposer and fish-eating apex predator described in
## sim_config.gd's "Decomposer"/"Apex predator" sections. Both are gated
## behind enable_decomposer/enable_apex_predator (default off), so this is
## the only place they currently run at all - the shipped loop and every
## other harness are untouched by their existence.
##
## This is deliberately a lighter bar than the phaseN_validate.gd scripts:
## there's no sweep-chosen combo to confirm here, just "does the scaffold's
## bookkeeping actually hold" - mass conservation across the now-8-term
## ledger (algae+nutrients+detritus+daphnia+fish+decomposer+apex_predator+
## respired), and no NaN/negative-population blowups. Real tuning (does
## the two-way detritus loop feel meaningful, is the apex predator
## appropriately rare/slow) is deferred until these are actually built out
## into the playable loop, per the design doc's own "don't tune a
## mechanism before confirming the simpler one works" principle (§11.4).
##
##   godot --headless --path . -s res://sim/harness/decomposer_apex_predator_check.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const TICK_COUNT := 54000

func _initialize() -> void:
	var config := SimConfig.new()
	config.enable_decomposer = true
	config.enable_apex_predator = true
	config.initial_detritus = 2.0
	config.initial_decomposer = 0.5
	config.initial_apex_predator = 0.1

	var sim := SimCore.new(42, config)

	var expected_total: float = config.initial_algae + config.initial_nutrients + config.initial_detritus \
		+ config.initial_daphnia + config.initial_fish + config.initial_decomposer + config.initial_apex_predator

	var max_drift := 0.0
	var max_drift_tick := 0
	var any_negative := false
	var any_nan := false

	for i in TICK_COUNT:
		sim.step()
		var s := sim.snapshot()

		for value in [s.algae, s.nutrients, s.detritus, s.daphnia, s.fish, s.decomposer, s.apex_predator, s.capacity]:
			if is_nan(value):
				any_nan = true
			if value < -1e-9:
				any_negative = true

		var total: float = s.algae + s.nutrients + s.detritus + s.daphnia + s.fish + s.decomposer + s.apex_predator + s.respired
		var drift := absf(total - expected_total)
		if drift > max_drift:
			max_drift = drift
			max_drift_tick = s.tick

	var final_state := sim.snapshot()
	print("decomposer/apex_predator scaffold check: expected_total=%.6f max_drift=%.10f at_tick=%d any_negative=%s any_nan=%s" % [
		expected_total, max_drift, max_drift_tick, any_negative, any_nan
	])
	print("final populations: algae=%.4f daphnia=%.4f fish=%.4f decomposer=%.4f apex_predator=%.4f detritus=%.4f nutrients=%.4f" % [
		final_state.algae, final_state.daphnia, final_state.fish, final_state.decomposer,
		final_state.apex_predator, final_state.detritus, final_state.nutrients
	])

	var conserved := max_drift < 1e-6 and not any_negative and not any_nan
	print("conserved=%s" % [conserved])
	quit()
