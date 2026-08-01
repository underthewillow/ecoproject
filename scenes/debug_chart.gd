extends Control

## Debug rendering for Phase 0/1 (§7): live line charts of raw sim state,
## no styling. Reads snapshots only — never touches the sim.

const SimCore = preload("res://sim/core/sim_core.gd")

const HISTORY_LIMIT := 600
const DEFAULT_SEED := 12345

## Sim time only advances 10 ticks/real-second at 1x (§3.1's 0.1s timestep),
## so reaching equilibria that take thousands of sim-seconds would mean
## sitting here for tens of minutes. Number keys pick a wall-clock multiplier;
## the headless harness scripts remain the source of truth for acceptance
## checks, this is purely for eyeballing the shape of a run.
const SPEED_KEYS := {
	KEY_1: 1.0,
	KEY_2: 10.0,
	KEY_3: 60.0,
	KEY_4: 300.0,
}
const MAX_FRAME_DELTA := 0.25

const SERIES := [
	{"field": "algae", "color": Color.LIME_GREEN},
	{"field": "nutrients", "color": Color.DEEP_SKY_BLUE},
	{"field": "detritus", "color": Color.SANDY_BROWN},
	{"field": "daphnia", "color": Color.GOLD},
	{"field": "fish", "color": Color.ORCHID},
	# Mean daphnia body size (§4.2) - the actual quantity Phase 4's
	# acceptance criterion is measured on: does it fall when fish are
	# present and recover when they're removed? Each series here
	# auto-scales independently (see _draw_series), so this reads
	# correctly regardless of its absolute range relative to the
	# population-count series above it.
	{"field": "daphnia_mean_size", "color": Color.CRIMSON},
]

var _sim: SimCore
var _accumulator := 0.0
var _histories: Dictionary = {}
var _time_scale := 1.0

func _ready() -> void:
	_sim = SimCore.new(DEFAULT_SEED)
	for series in SERIES:
		_histories[series.field] = PackedFloat32Array()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and SPEED_KEYS.has(event.keycode):
		_time_scale = SPEED_KEYS[event.keycode]

func _process(delta: float) -> void:
	_accumulator += minf(delta, MAX_FRAME_DELTA) * _time_scale
	while _accumulator >= SimCore.TICK_DT:
		_accumulator -= SimCore.TICK_DT
		_sim.step()
		var state = _sim.snapshot()
		for series in SERIES:
			var history: PackedFloat32Array = _histories[series.field]
			history.append(state.get(series.field))
			if history.size() > HISTORY_LIMIT:
				history = history.slice(history.size() - HISTORY_LIMIT)
			_histories[series.field] = history
	queue_redraw()

func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(8, 20),
		"speed=%sx (press 1-4)" % [int(_time_scale) if _time_scale >= 1.0 else _time_scale],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	var y_offset := 40
	for series in SERIES:
		var history: PackedFloat32Array = _histories[series.field]
		_draw_series(history, series.color)
		if history.size() > 0:
			draw_string(ThemeDB.fallback_font, Vector2(8, y_offset),
				"%s=%.3f" % [series.field, history[-1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, series.color)
			y_offset += 20

func _draw_series(history: PackedFloat32Array, color: Color) -> void:
	if history.size() < 2:
		return

	var min_v := history[0]
	var max_v := history[0]
	for v in history:
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	var range_v := maxf(max_v - min_v, 0.001)

	var points := PackedVector2Array()
	for i in history.size():
		var x := (float(i) / float(history.size() - 1)) * size.x
		var y := size.y - ((history[i] - min_v) / range_v) * size.y
		points.append(Vector2(x, y))

	draw_polyline(points, color, 2.0, true)
