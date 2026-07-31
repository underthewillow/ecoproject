extends Control

## Debug rendering for Phase 0 (§7): a live line chart of raw sim state,
## no styling. Reads snapshots only — never touches the sim.

const SimCore = preload("res://sim/core/sim_core.gd")

const HISTORY_LIMIT := 600
const DEFAULT_SEED := 12345

var _sim: SimCore
var _accumulator := 0.0
var _history: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	_sim = SimCore.new(DEFAULT_SEED)

func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SimCore.TICK_DT:
		_accumulator -= SimCore.TICK_DT
		_sim.step()
		_history.append(_sim.snapshot().sample)
		if _history.size() > HISTORY_LIMIT:
			_history = _history.slice(_history.size() - HISTORY_LIMIT)
	queue_redraw()

func _draw() -> void:
	if _history.size() < 2:
		return

	var min_v := _history[0]
	var max_v := _history[0]
	for v in _history:
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	var range_v := maxf(max_v - min_v, 0.001)

	var points := PackedVector2Array()
	for i in _history.size():
		var x := (float(i) / float(_history.size() - 1)) * size.x
		var y := size.y - ((_history[i] - min_v) / range_v) * size.y
		points.append(Vector2(x, y))

	draw_polyline(points, Color.LIME_GREEN, 2.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(8, 20), "sample=%.3f" % _history[-1])
