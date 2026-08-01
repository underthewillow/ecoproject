extends SceneTree

## Phase 4 acceptance check (§8): confirms the sweep's chosen size-
## dependent exponents (sweep_phase4.gd) produce §4.2's actual claim -
## "introduce fish and mean daphnia body size falls over generations.
## Remove the pressure and it climbs back" - across seeds and the full
## ~90 sim-minute session (54,000 ticks), not just the shorter
## exploration window the sweep used.
##
## Three checks:
## 1. Fish present throughout, 20 seeds, full duration: confirm the
##    three-way system still persists (Phase 3's own bar) and settles to
##    a LOW mean daphnia size.
## 2. Fish absent throughout, 20 seeds, full duration: confirm daphnia/
##    algae persist and mean size settles HIGH.
## 3. A single dynamic run (seed 0 - every seed is bit-identical right
##    now, see sweep_phase3.gd's header): fish present for the first
##    half, removed via SimCore.set_fish(0) at the midpoint, continues
##    for the second half. Confirms mean size actually falls then climbs
##    back WITHIN one run, not just that two separate runs differ - the
##    more literal reading of §4.2's claim.
##
##   godot --headless --path . -s res://sim/harness/phase4_validate.gd

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const TICK_COUNT := 54000
const SEED_COUNT := 20
const COLLAPSE_THRESHOLD := 0.01

func _initialize() -> void:
	_check_static_runs()
	_check_dynamic_run()
	quit()

func _check_static_runs() -> void:
	var with_fish_persisting := 0
	var without_fish_persisting := 0
	var with_fish_final_size := 0.0
	var without_fish_final_size := 0.0

	for seed_value in range(SEED_COUNT):
		var with_fish := _run_static(seed_value, true)
		var without_fish := _run_static(seed_value, false)

		if with_fish.persisting:
			with_fish_persisting += 1
		if without_fish.persisting:
			without_fish_persisting += 1

		if seed_value == 0:
			with_fish_final_size = with_fish.mean_size
			without_fish_final_size = without_fish.mean_size

			var mass_total: float = with_fish.final_state.algae + with_fish.final_state.nutrients \
				+ with_fish.final_state.detritus + with_fish.final_state.daphnia \
				+ with_fish.final_state.fish + with_fish.final_state.respired
			var expected_total: float = SimConfig.new().initial_algae + SimConfig.new().initial_nutrients \
				+ SimConfig.new().initial_detritus + SimConfig.new().initial_daphnia + SimConfig.new().initial_fish
			print("seed=0 mass check (with fish, incl. respired): total=%.6f expected=%.6f diff=%.8f" % [
				mass_total, expected_total, absf(mass_total - expected_total)
			])

	print("static runs: with_fish_persisting=%d/%d without_fish_persisting=%d/%d" % [
		with_fish_persisting, SEED_COUNT, without_fish_persisting, SEED_COUNT
	])
	print("seed=0 final mean size: with_fish=%.4f without_fish=%.4f gap=%.4f (expect without_fish > with_fish)" % [
		with_fish_final_size, without_fish_final_size, without_fish_final_size - with_fish_final_size
	])

func _run_static(seed_value: int, with_fish: bool) -> Dictionary:
	var config := SimConfig.new()
	if not with_fish:
		config.initial_fish = 0.0

	var sim := SimCore.new(seed_value, config)
	for i in TICK_COUNT:
		sim.step()

	var final_state := sim.snapshot()
	var persisting := final_state.daphnia >= COLLAPSE_THRESHOLD and (not with_fish or final_state.fish >= COLLAPSE_THRESHOLD)
	return {"persisting": persisting, "mean_size": final_state.daphnia_mean_size, "final_state": final_state}

func _check_dynamic_run() -> void:
	var config := SimConfig.new()
	var sim := SimCore.new(0, config)
	var half := TICK_COUNT / 2

	for i in half:
		sim.step()
	var midpoint_size: float = sim.snapshot().daphnia_mean_size

	sim.set_fish(0.0)
	for i in half:
		sim.step()
	var final_size: float = sim.snapshot().daphnia_mean_size

	var fell_then_rose := midpoint_size < config.initial_daphnia_mean_size and final_size > midpoint_size
	print("dynamic run: initial_mean_size=%.4f midpoint_mean_size=%.4f (fish present) final_mean_size=%.4f (fish removed at tick %d) fell_then_rose=%s" % [
		config.initial_daphnia_mean_size, midpoint_size, final_size, half, fell_then_rose
	])
