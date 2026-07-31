extends RefCounted

## Fixed-timestep, headless-capable sim core (§3.1). No rendering
## dependencies — safe to run under `godot --headless` for the sweep
## harness or the debug chart.
##
## Uses explicit preload for its own dependencies rather than the class_name
## global cache, since that cache is built by the editor and a pure
## `godot --headless -s ...` invocation (fresh checkout, CI) never triggers it.

const SimRNG = preload("res://sim/core/sim_rng.gd")
const SimState = preload("res://sim/core/sim_state.gd")

const TICK_DT := 0.1

var _rng: SimRNG
var _state := SimState.new()

func _init(seed_value: int) -> void:
	_rng = SimRNG.new(seed_value)

func step() -> void:
	_state.tick += 1
	_state.time += TICK_DT
	_state.sample += _rng.randfn(0.0, 1.0) * TICK_DT
	_state.sample = clampf(_state.sample, -50.0, 50.0)

func snapshot() -> SimState:
	return _state.duplicate_state()
