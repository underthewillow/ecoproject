extends Control

## Debug rendering for Phase 0/1 (§7), extended for Phase 5 (§8): live line
## charts of raw sim state, plus a minimal interactive panel for the two
## player verbs (§6) - introduce a species, add nutrients - so the sim is
## actually clickable before Track B's real UI/art exist. This
## intentionally breaks Track A's "no rendering dependencies" rule; see
## docs/pond-prototype-plan.md §8 and sim/harness/phase5_validate.gd's
## header for why Phase 5 needed a real interface to be a "playable
## prototype" at all, plus a scripted headless proxy for the actual
## legibility claim. No styling here either - Track B still owns the real
## presentation pass (§7, §8 Track B).

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

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
	# Phase 5 (§6.3): the pond's own life-support capacity, which funds
	# introductions and nutrients and grows faster the more trophic levels
	# currently coexist (see sim_core.gd's _trophic_diversity).
	{"field": "capacity", "color": Color.LIGHT_GOLDENROD},
]

const FOUNDER_DEFAULT := 2.0
const NUTRIENT_DEFAULT := 5.0

var _sim: SimCore
var _accumulator := 0.0
var _histories: Dictionary = {}
var _time_scale := 1.0
var _last_state = null

var _founder_spin: SpinBox
var _nutrient_spin: SpinBox
var _status_label: Label

func _ready() -> void:
	var config := SimConfig.new()
	# Phase 5's empty-pond start (§6.1): nothing exists until the player
	# puts it there. enable_collapse_restart opts into §1 pillar 3's "no
	# hard fail state" - Phases 1-4's own harnesses never set this, so
	# their already-validated dynamics are unaffected by it existing.
	config.initial_algae = 0.0
	config.initial_daphnia = 0.0
	config.initial_fish = 0.0
	config.enable_collapse_restart = true

	_sim = SimCore.new(DEFAULT_SEED, config)
	for series in SERIES:
		_histories[series.field] = PackedFloat32Array()
	_last_state = _sim.snapshot()
	_build_ui()

func _build_ui() -> void:
	var introduce_row := HBoxContainer.new()
	introduce_row.position = Vector2(8, 200)
	add_child(introduce_row)

	introduce_row.add_child(_make_label("Founder count:"))
	_founder_spin = SpinBox.new()
	_founder_spin.min_value = 0.5
	_founder_spin.max_value = 50.0
	_founder_spin.step = 0.5
	_founder_spin.value = FOUNDER_DEFAULT
	_founder_spin.custom_minimum_size = Vector2(80, 0)
	introduce_row.add_child(_founder_spin)

	introduce_row.add_child(_make_button("Introduce Algae", func(): _try_introduce("algae")))
	introduce_row.add_child(_make_button("Introduce Daphnia", func(): _try_introduce("daphnia")))
	introduce_row.add_child(_make_button("Introduce Fish", func(): _try_introduce("fish")))

	var nutrient_row := HBoxContainer.new()
	nutrient_row.position = Vector2(8, 236)
	add_child(nutrient_row)

	nutrient_row.add_child(_make_label("Nutrient amount:"))
	_nutrient_spin = SpinBox.new()
	_nutrient_spin.min_value = 0.5
	_nutrient_spin.max_value = 50.0
	_nutrient_spin.step = 0.5
	_nutrient_spin.value = NUTRIENT_DEFAULT
	_nutrient_spin.custom_minimum_size = Vector2(80, 0)
	nutrient_row.add_child(_nutrient_spin)

	nutrient_row.add_child(_make_button("Add Nutrients", func(): _sim.add_nutrients(_nutrient_spin.value)))

	var difficulty_row := HBoxContainer.new()
	difficulty_row.position = Vector2(8, 272)
	add_child(difficulty_row)

	difficulty_row.add_child(_make_label("Difficulty (time dilation):"))
	difficulty_row.add_child(_make_button("Challenging (1x)", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CHALLENGING])))
	difficulty_row.add_child(_make_button("Casual (0.5x)", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CASUAL])))
	difficulty_row.add_child(_make_button("Relaxing (0.25x)", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.RELAXING])))

	_status_label = Label.new()
	_status_label.position = Vector2(8, 308)
	add_child(_status_label)

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button

func _try_introduce(species: String) -> void:
	_sim.introduce_species(species, _founder_spin.value)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and SPEED_KEYS.has(event.keycode):
		_time_scale = SPEED_KEYS[event.keycode]

func _process(delta: float) -> void:
	_accumulator += minf(delta, MAX_FRAME_DELTA) * _time_scale
	while _accumulator >= SimCore.TICK_DT:
		_accumulator -= SimCore.TICK_DT
		_sim.step()
		var state = _sim.snapshot()
		_last_state = state
		for series in SERIES:
			var history: PackedFloat32Array = _histories[series.field]
			history.append(state.get(series.field))
			if history.size() > HISTORY_LIMIT:
				history = history.slice(history.size() - HISTORY_LIMIT)
			_histories[series.field] = history
	_update_status_label()
	queue_redraw()

func _update_status_label() -> void:
	if _status_label == null or _last_state == null:
		return
	var founder: float = _founder_spin.value if _founder_spin else 0.0
	_status_label.text = "pace=%.2fx  |  capacity=%.2f  |  cost preview (founder=%.1f): algae=%.2f daphnia=%.2f fish=%.2f  |  collapses=%d" % [
		_sim.get_pace_scale(), _last_state.capacity, founder,
		_sim.get_introduction_cost("algae", founder),
		_sim.get_introduction_cost("daphnia", founder),
		_sim.get_introduction_cost("fish", founder),
		_last_state.collapse_count,
	]

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
