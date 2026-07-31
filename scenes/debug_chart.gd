extends Control

## Debug rendering for Phase 0/1 (§7): live line charts of raw sim state,
## no styling. Reads snapshots only — never touches the sim.

const SimCore = preload("res://sim/core/sim_core.gd")

const HISTORY_LIMIT := 600
const DEFAULT_SEED := 12345

const SERIES := [
	{"field": "algae", "color": Color.LIME_GREEN},
	{"field": "nutrients", "color": Color.DEEP_SKY_BLUE},
	{"field": "detritus", "color": Color.SANDY_BROWN},
]

var _sim: SimCore
var _accumulator := 0.0
var _histories: Dictionary = {}

func _ready() -> void:
	_sim = SimCore.new(DEFAULT_SEED)
	for series in SERIES:
		_histories[series.field] = PackedFloat32Array()

func _process(delta: float) -> void:
	_accumulator += delta
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
	var y_offset := 20
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
