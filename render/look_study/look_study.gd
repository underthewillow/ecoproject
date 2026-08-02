extends Control

## Track B look study (§7.1, §8) - top-down view, painterly/bioluminescent
## art direction. Phase 6 (§8): this now reads a real SimCore instead of
## fake_pond_state.gd's sine wave - the renderer only ever needed
## population counts, which is exactly what made this safe to build
## independent of how far Track A had gotten, and exactly what makes the
## swap here a data-source change rather than a rewrite. pond_audio.gd
## still reads the fake data for now - wiring audio to real state is a
## separate, not-yet-done follow-up, so fake_pond_state.gd stays as is.
##
## This scene is also now the actual playable prototype, not just a visual
## study: it owns the two player verbs (introduce a species, add
## nutrients) and the difficulty toggle, ported over from
## scenes/debug_chart.gd. §7's "numbers stay hidden by default" is the
## long-term intent - capacity reads as a glow, nutrient load as a water
## tint, detritus as silt density, a collapse as a full-pond flash (see
## _draw()'s gauge helpers) - but direct feedback from actually playtesting
## this was that the numbers are still needed *right now* to judge whether
## any of it is tuned sensibly. See NUMERIC_OVERLAY_ENABLED below: the raw
## values are drawn as text too, meant to come back off once there's
## enough played experience to trust the visual gauges alone.
##
## Sprite counts track real population near-1:1 (see
## _resize_to_population) rather than through a normalized/log-scaled
## curve - an earlier pass mapped small founder counts through a reference
## scale meant for "how full does the screen look," which is exactly
## backwards for legibility: introducing 2 daphnia should show 2 daphnia.
## Populations are continuous (§4.1's trait bins track density, not
## headcount), so a fractional remainder renders as one additional,
## partially-grown individual rather than being rounded away - reproducing
## into a new whole individual becomes visible growth, not a pop-in.
##
## Background is a single real illustration (render/water/
## pond_background.png), not a procedural shader or tiled texture. That
## sidesteps the whole class of tiling/seam/pulsing-sweep bugs from the
## earlier attempts: a background filling one fixed viewport doesn't need
## to tile at all. Creature/prop art is likewise generated (OpenAI
## gpt-image-1 via the media-pipeline MCP server), not flat shapes or
## pixel art - see git history for why both of those were dropped.
##
## Predation is still cosmetic-only, driven by real counts rather than
## real individuals (§11.4: "the sim is a histogram, and the pond looks
## alive") - daphnia bias their hops toward the nearest algae in range,
## fish bias their darts toward the nearest daphnia, and "eating" just
## respawns the prey particle elsewhere with a brief flash. Nothing here
## writes back to the sim except the two player-verb calls below.

const SimCore = preload("res://sim/core/sim_core.gd")
const SimConfig = preload("res://sim/core/sim_config.gd")

const ALGAE_TEXTURE := preload("res://render/sprites/algae.png")
const DAPHNIA_TEXTURE := preload("res://render/sprites/daphnia.png")
const FISH_TEXTURE := preload("res://render/sprites/fish.png")
const LILYPAD_TEXTURES := [
	preload("res://render/sprites/lilypad1.png"),
	preload("res://render/sprites/lilypad2.png"),
]
const ROCK_TEXTURES := [
	preload("res://render/sprites/rock1.png"),
	preload("res://render/sprites/rock2.png"),
]

const ALGAE_SPRITE_SIZE := Vector2(22, 22)
const DAPHNIA_SPRITE_SIZE := Vector2(50, 50)
const FISH_SPRITE_SIZE := Vector2(56, 68)
const LILYPAD_SIZE_RANGE := Vector2(70, 110)
const ROCK_SIZE_RANGE := Vector2(36, 64)

## fish.png (v3, the "likeable" version with big eyes and a straight tail)
## was generated nose-UP - head/eyes at the top of the frame, tail at the
## bottom - the opposite of v2. Confirmed by inspecting the file each
## time, never assumed: regenerating with a similar prompt does not
## guarantee the same orientation twice, and it has flipped every time so
## far. draw_set_transform's rotation=0 points the image's own "up" (-Y)
## in that direction already, so the offset to align the nose with
## velocity is +90 degrees for this version.
const FISH_FACING_OFFSET := PI / 2.0

## Whether the tail occupies the TOP or BOTTOM of the source image - see
## _draw_fish(), which crops the image into a rigid body and a rotating
## tail. True for a nose-down fish (tail at top, like v2), false for
## nose-up (tail at bottom, like v3 - the current one). Check this
## alongside FISH_FACING_OFFSET any time fish.png is regenerated.
const FISH_TAIL_AT_TOP := false

## A single static image can't flex, so "swimming" is faked by splitting
## the image into a rigid body (drawn once, no wobble) and a tail region
## that rotates around the seam where it joins the body - see
## _draw_fish(). TAIL_FRACTION is the fraction of the source image the
## tail occupies - estimated by eye, not measured pixel-exact, so it's
## the first place to adjust if the seam looks wrong. Wobble is isolated
## to just the tail instead of the whole body, and reduced from the
## original 0.22 - the first pass rotated the entire fish and was called
## out as too much.
const FISH_TAIL_FRACTION := 0.3
const FISH_WOBBLE_AMPLITUDE := 0.16
const FISH_WOBBLE_BASE_FREQ := 4.0
const FISH_WOBBLE_SPEED_FACTOR := 0.03

## Seam-feathering (see _draw_fish_tail_feathered) - the fraction of the
## tail's length, nearest the body, over which it fades in from
## FISH_TAIL_SEAM_MIN_ALPHA to fully opaque. More steps = smoother
## gradient at the cost of more draw calls per fish per frame; negligible
## at FISH_MAX_PARTICLES's scale.
const FISH_TAIL_SEAM_FEATHER_FRACTION := 0.35
const FISH_TAIL_SEAM_MIN_ALPHA := 0.12
const FISH_TAIL_SEAM_FEATHER_STEPS := 6

## daphnia.png has its antennae pointing toward the top of the frame
## (confirmed by inspection) - same nose-up convention as the fish, so
## the same +90 degree offset applies.
const DAPHNIA_FACING_OFFSET := PI / 2.0

const ALGAE_POP_COLOR := Color(0.55, 0.85, 0.5)
const DAPHNIA_POP_COLOR := Color(0.75, 0.88, 0.95)
const FISH_POP_COLOR := Color(1.0, 0.72, 0.25)

## Ceilings for the near-1:1 population->sprite mapping (see
## _resize_to_population) - not a "how full does the screen look"
## normalization anymore, just a hard cap so an extreme founder count
## (or an explosive bloom) can't ever spawn an unbounded number of
## draw calls. Algae/daphnia already comfortably cover the ranges observed
## across the Track A harnesses (algae's own carrying capacity is 60;
## daphnia blooms have been observed up to ~20). Fish is raised well above
## its old value since a deliberately large fish founder should still
## read close to 1:1 rather than being invisibly clipped at 10.
const ALGAE_MAX_PARTICLES := 150
const DAPHNIA_MAX_PARTICLES := 80
const FISH_MAX_PARTICLES := 25

## Silt isn't a species a player introduces via founder count, so it keeps
## the earlier reference-scale/log-curve treatment (see
## _population_to_count) rather than the near-1:1 mapping above - it's
## meant to read as "how murky/silty," not as a literal count.
const DETRITUS_REFERENCE_LEVEL := 15.0
const NUTRIENT_TINT_REFERENCE_LEVEL := 25.0
const CAPACITY_GAUGE_REFERENCE_LEVEL := 200.0

## Fractional remainder below which no partially-grown "budding" individual
## is shown at all - avoids a barely-visible sliver appearing/disappearing
## right at the rounding boundary.
const GROWTH_BUD_MIN_FRACTION := 0.02
const GROWTH_BUD_MIN_SCALE := 0.15

## A population change at or above this in a single real tick (0.1
## sim-seconds) is treated as a discrete event (a founder introduction, or
## an explosive bloom) rather than smooth reproduction, and skips the
## growing-bud animation for that update - see _resize_to_population.
## Smooth per-tick ecological change is normally well under this even
## during fast growth (observed well under 0.1/tick in practice); the
## smallest legal founder introduction (the founder SpinBox's min_value)
## is 0.5, comfortably above it.
const POPULATION_JUMP_THRESHOLD := 0.3

## Numbers are still needed to playtest (direct feedback) even though §7's
## long-term intent is to hide them - see the top-of-file docstring. Flip
## to false once the visual gauges alone are trusted.
const NUMERIC_OVERLAY_ENABLED := true

## Daphnia's rendered size follows the real evolutionary signal (§4.2) -
## sim_config.gd's daphnia_reference_size (1.0) is the sprite's designed
## scale, and daphnia_size_min/max (0.5/2.0) is the full trait range; this
## clamps the visual range slightly inside that so it never reads as
## vanishingly tiny or absurdly oversized on screen.
const DAPHNIA_REFERENCE_TRAIT_SIZE := 1.0
const DAPHNIA_VISUAL_SIZE_SCALE_RANGE := Vector2(0.5, 1.8)

## Visual gauges for capacity/nutrients/detritus/collapse (§7's "numbers
## stay hidden by default" - diagnose the pond by looking, not by reading).
const CAPACITY_GAUGE_POSITION := Vector2(40, 40)
const CAPACITY_GAUGE_MIN_RADIUS := 6.0
const CAPACITY_GAUGE_MAX_RADIUS := 22.0
const CAPACITY_GAUGE_COLOR := Color(0.6, 0.95, 0.85)

const NUTRIENT_TINT_COLOR := Color(0.45, 0.42, 0.18)
const NUTRIENT_TINT_MAX_ALPHA := 0.28

const COLLAPSE_FLASH_COLOR := Color(1.0, 1.0, 1.0)
const COLLAPSE_FLASH_DURATION := 1.2

const FOUNDER_DEFAULT := 2.0
const NUTRIENT_AMOUNT_DEFAULT := 5.0

const DAPHNIA_HOP_STRENGTH := 65.0
const DAPHNIA_DAMPING := 8.0
const DAPHNIA_SINK_SPEED := 4.0
const DAPHNIA_DETECT_RADIUS := 140.0
const DAPHNIA_EAT_RADIUS := 16.0

const FISH_GLIDE_SPEED := 18.0
const FISH_DART_SPEED := 65.0
const FISH_DETECT_RADIUS := 90.0
const FISH_EAT_RADIUS := 16.0

## How much real biomass (see SimState's algae_grazed_this_tick/
## daphnia_predated_this_tick) one visible eat-flash "costs" - this is what
## actually paces flash frequency to the real consumption rate, replacing
## a fixed per-predator cooldown that had no relationship to the numbers.
## First-guess values, same caveat as everything else calibrated by feel:
## sized against typical observed grazing/predation rates (roughly
## 0.5-1.5/sim-second during healthy grazing, an order of magnitude less
## for predation, which is rarer by design) so flashes read as frequent-
## but-discrete rather than a constant strobe or a near-never event.
## Credit is capped at a few multiples of the per-flash cost so a long
## quiet stretch (no predator in range) doesn't bank an unbounded backlog
## that then bursts unrealistically once one wanders back into range.
const ALGAE_EATEN_PER_FLASH := 0.4
const DAPHNIA_EATEN_PER_FLASH := 0.04
const EAT_CREDIT_MAX_BANK_MULTIPLE := 4.0

## Global (not per-predator) minimum spacing between two eat-flash events
## of the same trophic level, even when there's enough banked credit for
## several at once. pond_audio.gd's interaction chimes are deliberately
## un-throttled on the audio side (round-robin, no cooldown - see its own
## comment: an earlier single-voice-with-cooldown design silently dropped
## events, which was worse), on the assumption that events arrive at a
## naturally spaced pace. The old per-individual eat cooldown used to
## guarantee that spacing as a side effect; removing it for credit-based
## pacing meant a bank of up to EAT_CREDIT_MAX_BANK_MULTIPLE credits could
## release in a near-simultaneous burst (several daphnia converging on the
## same algae, which their own chase-the-nearest behavior encourages),
## hitting all 3 chime voices back-to-back before any had decayed -
## reported directly as "crunch/clipping distortion sounds." This restores
## a minimum gap, but globally across all predators of one type rather
## than per-individual, so the overall rate still tracks real consumption
## (the credit system's whole point) while bursts get smoothed into a
## steady trickle instead of firing all at once.
const ALGAE_EAT_MIN_INTERVAL := 0.25
const DAPHNIA_EAT_MIN_INTERVAL := 0.4

const POP_DURATION := 0.5

## Silt's COUNT is not a species population, but its density now tracks
## real detritus (§7's "detritus accumulation" being one of the four things
## a player should be able to diagnose by looking) - SILT_COUNT is the
## ceiling that maps to DETRITUS_REFERENCE_LEVEL, not a fixed decoration
## anymore. Rocks and lily pads stay purely decorative, no sim tie.
const SILT_COUNT := 40
const ROCK_COUNT := 4
const LILYPAD_COUNT := 5

var _sim: SimCore
var _time := 0.0  # decorative-only: drift/current phase for algae and silt, unrelated to sim ticks
var _tick_accumulator := 0.0
var _last_state = null
var _last_collapse_count := 0
var _collapse_flash_timer := 0.0
var _daphnia_size_scale := 1.0

## Per-species previous population, for _resize_to_population's discrete-
## jump detection (see POPULATION_JUMP_THRESHOLD).
var _algae_prev_population := 0.0
var _daphnia_prev_population := 0.0
var _fish_prev_population := 0.0

## "Banked" real biomass consumed but not yet spent on a visible eat-flash
## - see _spend_eat_credit. Real consumption happens smoothly every tick;
## a visible bite is a discrete event, so credit accumulates continuously
## and gets spent in fixed-size chunks whenever a predator happens to be
## in range, which is what actually ties flash frequency to the real rate
## instead of an arbitrary cooldown.
var _algae_eat_credit := 0.0
var _daphnia_eat_credit := 0.0

## Global cooldowns enforcing ALGAE_EAT_MIN_INTERVAL/DAPHNIA_EAT_MIN_INTERVAL
## - see those constants for why this exists alongside the credit system.
var _algae_eat_cooldown := 0.0
var _daphnia_eat_cooldown := 0.0

var _algae: Array[Dictionary] = []
var _daphnia: Array[Dictionary] = []
var _fish: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _silt: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _lilypads: Array[Dictionary] = []

var _founder_spin: SpinBox
var _nutrient_spin: SpinBox
var _algae_button: Button
var _daphnia_button: Button
var _fish_button: Button
var _nutrient_button: Button

func _ready() -> void:
	randomize()  # cosmetic layer only - no determinism requirement here, unlike the sim's seeded RNG

	var config := SimConfig.new()
	# Empty-pond start (§6.1) - same Phase 5 setup as debug_chart.gd:
	# nothing exists until the player puts it there, and a crashed pond
	# gets to restart rather than end the session (§1 pillar 3).
	config.initial_algae = 0.0
	config.initial_daphnia = 0.0
	config.initial_fish = 0.0
	config.enable_collapse_restart = true
	_sim = SimCore.new(randi(), config)
	_last_state = _sim.snapshot()

	for i in ROCK_COUNT:
		_rocks.append(_spawn_rock())
	for i in LILYPAD_COUNT:
		_lilypads.append(_spawn_lilypad())
	_build_ui()

## The two player verbs (§6), ported over from scenes/debug_chart.gd now
## that this is the real playable scene. No numeric cost/capacity preview
## here (unlike debug_chart's) - §7 wants numbers hidden by default, so
## affordability is communicated by disabling a button rather than
## printing what it costs (see _update_affordability).
func _build_ui() -> void:
	var introduce_row := HBoxContainer.new()
	introduce_row.position = Vector2(8, 8)
	add_child(introduce_row)

	introduce_row.add_child(_make_label("Founder count:"))
	_founder_spin = SpinBox.new()
	_founder_spin.min_value = 0.5
	_founder_spin.max_value = 50.0
	_founder_spin.step = 0.5
	_founder_spin.value = FOUNDER_DEFAULT
	_founder_spin.custom_minimum_size = Vector2(80, 0)
	introduce_row.add_child(_founder_spin)

	_algae_button = _make_button("Introduce Algae", func(): _sim.introduce_species("algae", _founder_spin.value))
	_daphnia_button = _make_button("Introduce Daphnia", func(): _sim.introduce_species("daphnia", _founder_spin.value))
	_fish_button = _make_button("Introduce Fish", func(): _sim.introduce_species("fish", _founder_spin.value))
	introduce_row.add_child(_algae_button)
	introduce_row.add_child(_daphnia_button)
	introduce_row.add_child(_fish_button)

	var nutrient_row := HBoxContainer.new()
	nutrient_row.position = Vector2(8, 44)
	add_child(nutrient_row)

	nutrient_row.add_child(_make_label("Nutrient amount:"))
	_nutrient_spin = SpinBox.new()
	_nutrient_spin.min_value = 0.5
	_nutrient_spin.max_value = 50.0
	_nutrient_spin.step = 0.5
	_nutrient_spin.value = NUTRIENT_AMOUNT_DEFAULT
	_nutrient_spin.custom_minimum_size = Vector2(80, 0)
	nutrient_row.add_child(_nutrient_spin)

	_nutrient_button = _make_button("Add Nutrients", func(): _sim.add_nutrients(_nutrient_spin.value))
	nutrient_row.add_child(_nutrient_button)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.position = Vector2(8, 80)
	add_child(difficulty_row)

	difficulty_row.add_child(_make_label("Difficulty:"))
	difficulty_row.add_child(_make_button("Challenging", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CHALLENGING])))
	difficulty_row.add_child(_make_button("Casual", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CASUAL])))
	difficulty_row.add_child(_make_button("Relaxing", func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.RELAXING])))

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button

## Non-numeric affordability cue (§7 - no cost/capacity numbers shown):
## grey out whichever introduce/nutrient action the player currently can't
## afford, checked every frame against the live spinbox values rather than
## only on sim ticks, since the player can change those values faster than
## the sim advances.
func _update_affordability() -> void:
	if _last_state == null:
		return
	var capacity: float = _last_state.capacity
	_algae_button.disabled = _sim.get_introduction_cost("algae", _founder_spin.value) > capacity
	_daphnia_button.disabled = _sim.get_introduction_cost("daphnia", _founder_spin.value) > capacity
	_fish_button.disabled = _sim.get_introduction_cost("fish", _founder_spin.value) > capacity
	_nutrient_button.disabled = _sim.get_nutrient_cost(_nutrient_spin.value) > capacity

func _process(delta: float) -> void:
	_time += delta
	_step_sim_ticks(delta)
	_collapse_flash_timer = maxf(_collapse_flash_timer - delta, 0.0)
	_algae_eat_cooldown = maxf(_algae_eat_cooldown - delta, 0.0)
	_daphnia_eat_cooldown = maxf(_daphnia_eat_cooldown - delta, 0.0)
	_update_affordability()
	_step_algae(delta)
	_step_daphnia(delta)
	_step_fish(delta)
	_step_pops(delta)
	_step_silt(delta)
	_step_lilypads(delta)
	queue_redraw()

## Steps the real sim at its own fixed timestep (SimCore.TICK_DT), separate
## from the continuous per-render-frame motion in _step_algae/_step_daphnia/
## _step_fish below - "how many particles" is tied to real discrete
## ecological ticks, "how each particle currently moves" is tied to smooth
## wall-clock delta, matching the same separation debug_chart.gd uses.
func _step_sim_ticks(delta: float) -> void:
	_tick_accumulator += minf(delta, 0.25)
	var stepped := false
	while _tick_accumulator >= SimCore.TICK_DT:
		_tick_accumulator -= SimCore.TICK_DT
		_sim.step()
		stepped = true
		# Accumulated per individual tick (not just once after the loop,
		# in case more than one tick executes in a single frame) - see
		# ALGAE_EATEN_PER_FLASH/DAPHNIA_EATEN_PER_FLASH.
		var consumption := _sim.get_last_tick_consumption()
		_algae_eat_credit = minf(_algae_eat_credit + consumption.algae_grazed, ALGAE_EATEN_PER_FLASH * EAT_CREDIT_MAX_BANK_MULTIPLE)
		_daphnia_eat_credit = minf(_daphnia_eat_credit + consumption.daphnia_predated, DAPHNIA_EATEN_PER_FLASH * EAT_CREDIT_MAX_BANK_MULTIPLE)
	if not stepped:
		return

	var state = _sim.snapshot()
	if state.collapse_count > _last_collapse_count:
		_collapse_flash_timer = COLLAPSE_FLASH_DURATION
		PondEvents.collapse.emit()
	_last_collapse_count = state.collapse_count
	_last_state = state

	_update_population_targets(state)
	_daphnia_size_scale = clampf(state.daphnia_mean_size / DAPHNIA_REFERENCE_TRAIT_SIZE, DAPHNIA_VISUAL_SIZE_SCALE_RANGE.x, DAPHNIA_VISUAL_SIZE_SCALE_RANGE.y)

## Log-scaled, hard-capped mapping used only for silt/detritus now (see the
## const comments above) - normalizes against a reference "abundant" level
## so it reads 0 at population=0 and approaches max_particles as the value
## approaches (and exceeds) reference_level, rather than needing an exact
## count to fill the screen. Species sprite counts use
## _resize_to_population below instead, which is closer to 1:1.
func _population_to_count(population: float, reference_level: float, max_particles: int) -> int:
	var scaled := log(maxf(population, 0.0) + 1.0) / log(reference_level + 1.0) * float(max_particles)
	return clampi(int(scaled), 0, max_particles)

func _update_population_targets(state) -> void:
	_algae_prev_population = _resize_to_population(_algae, state.algae, ALGAE_MAX_PARTICLES, _spawn_algae, _algae_prev_population)
	_daphnia_prev_population = _resize_to_population(_daphnia, state.daphnia, DAPHNIA_MAX_PARTICLES, _spawn_daphnia, _daphnia_prev_population)
	_fish_prev_population = _resize_to_population(_fish, state.fish, FISH_MAX_PARTICLES, _spawn_fish, _fish_prev_population)
	_resize(_silt, _population_to_count(state.detritus, DETRITUS_REFERENCE_LEVEL, SILT_COUNT), _spawn_silt)

func _resize(list: Array[Dictionary], target_count: int, spawn_fn: Callable) -> void:
	while list.size() < target_count:
		list.append(spawn_fn.call())
	while list.size() > target_count:
		list.pop_back()

## Near-1:1 mapping from a real (continuous) population to particle
## instances - see the top-of-file docstring for why this replaced a
## log-scaled/normalized approach. whole_count individuals render at full
## size (grow_scale=1.0); any leftover fraction renders as one additional
## partially-grown individual instead of being rounded away, so
## reproducing into a new whole individual is visible growth rather than
## an instant pop-in. That budding individual is a real list entry - it
## drifts/hops/glides via the same _step_* functions as everything else,
## just smaller - so it reads as "a small one," not as a UI artifact.
##
## Two very different histories can produce the same population number -
## smooth reproduction/death, or a discrete founder introduction/collapse -
## and they need different treatment, which is why this dispatches on
## prev_population's jump size (see _apply_smooth_growth /
## _apply_population_jump) rather than using one formula for both. An
## earlier single-formula version recomputed the WHOLE list from scratch
## every call, unconditionally resetting every entry to full size and then
## re-applying the fractional scale to whichever entry ended up last.
## Directly reported twice: first, a fish population reading 1.6 (1 full +
## 1 at 0.6) that, after introducing another fish and reaching 2.6, showed
## 1 full and TWO stuck-at-0.6 fish instead of 2 full + 1 new bud. Fixing
## that by resetting every entry each call created a second bug: on the
## very introduction that should add a distinct new full-size individual,
## the pre-existing bud got swept up in the "reset everything, then mark
## whichever is last as the bud" reshuffle - visually, the OLD partial
## sprite jumped to full size and a NEW partial appeared elsewhere, instead
## of the old partial continuing undisturbed and the founder itself simply
## being new and full. Returns the clamped population so the caller can
## update its prev_population tracker.
func _resize_to_population(list: Array[Dictionary], population: float, max_particles: int, spawn_fn: Callable, prev_population: float) -> float:
	var clamped: float = clampf(population, 0.0, float(max_particles))
	var delta := clamped - prev_population

	if absf(delta) >= POPULATION_JUMP_THRESHOLD:
		_apply_population_jump(list, delta, max_particles, spawn_fn)
	else:
		_apply_smooth_growth(list, clamped, max_particles, spawn_fn)

	return clamped

## Smooth, continuous change (ordinary tick-by-tick reproduction/death).
## The bud is tracked by an explicit "is_bud" marker on its own dict entry,
## not by array position ("whichever entry happens to be last") - a jump
## can append a brand new entry after the bud (see _apply_population_jump),
## which would silently make the FOUNDER "last" instead of the bud, so a
## positional convention would just relocate the original bug one tick
## later: the very next smooth-growth call would promote the pre-existing
## bud (no longer last) to full and start shrinking the founder (now last)
## down to the fractional remainder - the same swap the user reported,
## just delayed by a tick instead of fixed. Tracking identity explicitly
## means the bud keeps being the SAME sprite across calls regardless of
## what else gets added or removed around it, and a founder introduced as
## full stays full until it naturally, individually declines on its own.
func _apply_smooth_growth(list: Array[Dictionary], clamped: float, max_particles: int, spawn_fn: Callable) -> void:
	var whole := int(floor(clamped))
	var fractional := clamped - float(whole)
	var has_bud := fractional > GROWTH_BUD_MIN_FRACTION

	var bud_index := _find_bud_index(list)
	var plain_count := list.size() - (1 if bud_index >= 0 else 0)

	# Reconcile the whole/plain count first - growing plain_count up to
	# `whole` preferentially promotes the existing bud in place (it just
	# finished growing into a complete individual) before spawning any
	# brand new ones; shrinking plain_count down removes a plain entry,
	# never the bud.
	while plain_count < whole:
		if bud_index >= 0:
			list[bud_index]["grow_scale"] = 1.0
			list[bud_index].erase("is_bud")
			bud_index = -1
		elif list.size() < max_particles:
			var entry: Dictionary = spawn_fn.call()
			entry["grow_scale"] = 1.0
			list.append(entry)
		else:
			break
		plain_count += 1
	while plain_count > whole:
		var idx := _find_non_bud_index(list)
		if idx < 0:
			break
		list.remove_at(idx)
		bud_index = _find_bud_index(list)
		plain_count -= 1

	if has_bud:
		if bud_index < 0:
			if list.size() < max_particles:
				var entry: Dictionary = spawn_fn.call()
				entry["grow_scale"] = clampf(fractional, GROWTH_BUD_MIN_SCALE, 1.0)
				entry["is_bud"] = true
				list.append(entry)
		else:
			list[bud_index]["grow_scale"] = clampf(fractional, GROWTH_BUD_MIN_SCALE, 1.0)
	elif bud_index >= 0:
		# The fractional remainder shrank away without reaching a whole
		# individual (population declined within the same integer
		# bracket) - the bud dies rather than being promoted.
		list.remove_at(bud_index)

func _find_bud_index(list: Array[Dictionary]) -> int:
	for i in list.size():
		if list[i].get("is_bud", false):
			return i
	return -1

func _find_non_bud_index(list: Array[Dictionary]) -> int:
	for i in list.size():
		if not list[i].get("is_bud", false):
			return i
	return -1

## A discrete event - a founder introduction (delta > 0) or a sudden wipe
## like a collapse (delta < 0) - touches only what actually changed and
## leaves everything else exactly as it was. In particular, an existing
## partially-grown bud keeps its own progress rather than being promoted
## or reshuffled: "founders should come in full size" means the NEW
## individuals are full and separate, not that whatever was already
## growing gets absorbed into representing them.
func _apply_population_jump(list: Array[Dictionary], delta: float, max_particles: int, spawn_fn: Callable) -> void:
	if delta > 0.0:
		# max(1, ...): round() alone can floor a jump right back to zero
		# effect - anything under 0.5 rounds to 0 - which would silently
		# drop a jump that was, by definition (it crossed
		# POPULATION_JUMP_THRESHOLD, currently 0.3), too big to be smooth
		# growth. A real founder introduction is always >= 0.5 (the
		# SpinBox's own minimum) so this only ever bites in the narrow
		# threshold-to-0.5 gap, but silently doing nothing there is worse
		# than slightly overshooting by rendering at least one individual.
		var new_count := maxi(1, int(round(delta)))
		for i in new_count:
			if list.size() >= max_particles:
				break
			var entry: Dictionary = spawn_fn.call()
			entry["grow_scale"] = 1.0
			list.append(entry)
	else:
		var remove_count := maxi(1, int(round(-delta)))
		for i in remove_count:
			if list.is_empty():
				break
			list.pop_back()

func _spawn_algae() -> Dictionary:
	return {"pos": _random_position(), "drift_phase": randf() * TAU}

func _spawn_daphnia() -> Dictionary:
	var facing := Vector2.UP.rotated(randf() * TAU)
	return {"pos": _random_position(), "vel": Vector2.ZERO, "facing": facing, "hop_timer": randf_range(0.4, 1.4)}

func _spawn_fish() -> Dictionary:
	var angle := randf() * TAU
	return {
		"pos": _random_position(),
		"vel": Vector2.RIGHT.rotated(angle) * FISH_GLIDE_SPEED,
		"dart_timer": randf_range(4.0, 9.0),
		"wobble_phase": randf() * TAU,
	}

func _spawn_silt() -> Dictionary:
	return {"pos": _random_position(), "drift_phase": randf() * TAU, "depth": randf()}

func _spawn_rock() -> Dictionary:
	return {
		"pos": _random_position(),
		"texture": ROCK_TEXTURES[randi() % ROCK_TEXTURES.size()],
		"size": randf_range(ROCK_SIZE_RANGE.x, ROCK_SIZE_RANGE.y),
		"rotation": randf() * TAU,
	}

## sway_phase/sway_speed give lily pads a very slow idle rotation wobble
## so they don't read as a dead, pasted-on decal - real pads drift a
## little even in still water.
func _spawn_lilypad() -> Dictionary:
	return {
		"pos": _random_position(),
		"texture": LILYPAD_TEXTURES[randi() % LILYPAD_TEXTURES.size()],
		"size": randf_range(LILYPAD_SIZE_RANGE.x, LILYPAD_SIZE_RANGE.y),
		"base_rotation": randf() * TAU,
		"sway_phase": randf() * TAU,
		"sway_speed": randf_range(0.15, 0.3),
	}

func _random_position() -> Vector2:
	return Vector2(randf() * size.x, randf() * size.y)

## Algae has no agency (§7.1) - it drifts on a slow, shared current plus a
## little per-particle wobble, never a direction of its own choosing, and
## never reacts to being hunted. Getting eaten just means some daphnia
## replaced it with a fresh one elsewhere (see _try_eat).
func _step_algae(delta: float) -> void:
	var current := Vector2(sin(_time * 0.08), cos(_time * 0.05)) * 4.0
	for a in _algae:
		a.drift_phase += delta * 0.35
		var wobble := Vector2(sin(a.drift_phase), cos(a.drift_phase * 1.3)) * 2.0
		a.pos += (current + wobble) * delta
		_contain(a)

## Silt drifts even more passively than algae - slower current, no wobble
## bias toward anything, never interacts with predation or population
## counts.
func _step_silt(delta: float) -> void:
	var current := Vector2(sin(_time * 0.05), cos(_time * 0.04)) * 2.0
	for s in _silt:
		s.drift_phase += delta * 0.2
		var wobble := Vector2(sin(s.drift_phase), cos(s.drift_phase * 0.7)) * 1.0
		s.pos += (current + wobble) * delta * (0.4 + s.depth * 0.6)
		_contain(s)

func _step_lilypads(delta: float) -> void:
	for p in _lilypads:
		p.sway_phase += delta * p.sway_speed

## Daphnia hop and jerk (§7.1) - discrete, erratic vertical bursts, not
## smooth drift. Hops bias toward the nearest algae in range (still with
## some randomness and the upward jerk mixed in, so it stays jerky rather
## than reading as a smart chase), and eating just triggers when close.
func _step_daphnia(delta: float) -> void:
	for d in _daphnia:
		d.hop_timer -= delta
		if d.hop_timer <= 0.0:
			d.hop_timer = randf_range(0.4, 1.4)
			var target_index := _find_nearest(d.pos, _algae, DAPHNIA_DETECT_RADIUS)
			var direction: Vector2
			if target_index >= 0:
				direction = (_algae[target_index].pos - d.pos).normalized()
				direction.y -= 0.12  # a little of the characteristic upward jerk even while chasing, but mostly a direct line to the target now
				direction = direction.normalized()
			else:
				direction = Vector2(randf_range(-0.4, 0.4), -1.0).normalized()
			d.vel = direction * DAPHNIA_HOP_STRENGTH * randf_range(0.6, 1.2)
			# Facing is set once per hop, not derived from the live (decaying)
			# velocity - otherwise it would snap toward angle 0 every time
			# vel damps to exactly zero between hops instead of holding the
			# last jerk's direction.
			d.facing = direction
		d.vel = d.vel.move_toward(Vector2.ZERO, DAPHNIA_DAMPING * DAPHNIA_HOP_STRENGTH * delta)
		d.pos += d.vel * delta
		d.pos.y += DAPHNIA_SINK_SPEED * delta
		_contain(d)
		_try_eat(d, _algae, DAPHNIA_EAT_RADIUS, ALGAE_POP_COLOR, _spawn_algae, 0)

## Fish glide, then dart (§7.1) - long low-effort coasting punctuated by
## sudden acceleration. Darts aim at the nearest daphnia in range when one
## exists, otherwise a random turn, keeping the same glide/dart rhythm
## either way.
func _step_fish(delta: float) -> void:
	for f in _fish:
		f.dart_timer -= delta
		if f.dart_timer <= 0.0:
			f.dart_timer = randf_range(4.0, 9.0)
			var target_index := _find_nearest(f.pos, _daphnia, FISH_DETECT_RADIUS)
			if target_index >= 0:
				f.vel = (_daphnia[target_index].pos - f.pos).normalized() * FISH_DART_SPEED
			else:
				var turn := randf_range(-1.2, 1.2)
				f.vel = f.vel.rotated(turn).normalized() * FISH_DART_SPEED
		# Glide decay is much gentler than the dart itself, so most of a
		# fish's time reads as coasting, not accelerating.
		f.vel = f.vel.move_toward(f.vel.normalized() * FISH_GLIDE_SPEED, FISH_GLIDE_SPEED * 0.4 * delta)
		f.pos += f.vel * delta
		f.wobble_phase += delta * (FISH_WOBBLE_BASE_FREQ + f.vel.length() * FISH_WOBBLE_SPEED_FACTOR)
		_contain(f)
		_try_eat(f, _daphnia, FISH_EAT_RADIUS, DAPHNIA_POP_COLOR, _spawn_daphnia, 1)

## "Eating" is purely cosmetic: the nearest prey within eat_radius gets
## replaced by a freshly spawned one elsewhere, so the population count
## stays exactly what _update_population_targets says it should be - only
## individual identity changes, which is all the eye can tell apart anyway.
##
## Gated by real consumption credit (see _spend_eat_credit), not a fixed
## per-predator cooldown - a predator being in range is necessary but not
## sufficient; it also has to be justified by the real grazing/predation
## already happening in the sim that tick. This is what actually ties
## visual frequency to the numbers: direct feedback was that eating flashes
## happened "kind of infrequently" and didn't line up with how fast the
## real counts were moving, because the old cooldown had no relationship
## to the real rate at all. Also announces the event via the PondEvents
## autoload (trophic_level: 0 for daphnia-eats-algae, 1 for
## fish-eats-daphnia) so the audio system can react without this script
## knowing or caring that anything is listening - see render/pond_events.gd.
func _try_eat(eater: Dictionary, prey_list: Array[Dictionary], eat_radius: float, pop_color: Color, respawn_fn: Callable, trophic_level: int) -> bool:
	var idx := _find_nearest(eater.pos, prey_list, eat_radius)
	if idx < 0:
		return false
	if not _spend_eat_credit(trophic_level):
		return false
	_pops.append({"pos": prey_list[idx].pos, "color": pop_color, "age": 0.0})
	prey_list[idx] = respawn_fn.call()
	PondEvents.predation.emit(trophic_level)
	return true

## trophic_level 0 = daphnia eating algae, 1 = fish eating daphnia -
## matches PondEvents.predation's own convention. Spends a fixed chunk of
## the banked real-consumption credit (see _algae_eat_credit/
## _daphnia_eat_credit) per visible bite; returns false (no bite) if there
## isn't enough banked yet, which naturally self-limits multiple nearby
## predators to however many bites the real rate can actually justify.
##
## Also gated by a global cooldown (ALGAE_EAT_MIN_INTERVAL/
## DAPHNIA_EAT_MIN_INTERVAL) independent of the credit check - credit alone
## would let several banked bites release in the same frame whenever
## multiple predators happen to be in range at once (their own
## chase-the-nearest behavior encourages exactly that convergence), which
## is what caused the reported audio crunch: pond_audio.gd's interaction
## chimes are deliberately un-throttled, so a burst of near-simultaneous
## PondEvents.predation signals hit all 3 round-robin voices back-to-back
## before any had decayed. The cooldown spaces bites out even when credit
## would otherwise allow a burst, without changing the average rate the
## credit system establishes.
func _spend_eat_credit(trophic_level: int) -> bool:
	if trophic_level == 0:
		if _algae_eat_credit < ALGAE_EATEN_PER_FLASH or _algae_eat_cooldown > 0.0:
			return false
		_algae_eat_credit -= ALGAE_EATEN_PER_FLASH
		_algae_eat_cooldown = ALGAE_EAT_MIN_INTERVAL
		return true
	else:
		if _daphnia_eat_credit < DAPHNIA_EATEN_PER_FLASH or _daphnia_eat_cooldown > 0.0:
			return false
		_daphnia_eat_credit -= DAPHNIA_EATEN_PER_FLASH
		_daphnia_eat_cooldown = DAPHNIA_EAT_MIN_INTERVAL
		return true

func _find_nearest(pos: Vector2, list: Array[Dictionary], max_radius: float) -> int:
	var best_index := -1
	var best_dist := max_radius
	for i in list.size():
		var dist := pos.distance_to(list[i].pos)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	return best_index

func _step_pops(delta: float) -> void:
	for p in _pops:
		p.age += delta
	_pops = _pops.filter(func(p): return p.age < POP_DURATION)

## Contain rather than wrap: a pond has edges, so a particle sliding off
## one side and reappearing on the other would read as a screen glitch,
## not a boundary.
func _contain(particle: Dictionary) -> void:
	if particle.pos.x < 0.0:
		particle.pos.x = 0.0
		if particle.has("vel"):
			particle.vel.x = absf(particle.vel.x)
	elif particle.pos.x > size.x:
		particle.pos.x = size.x
		if particle.has("vel"):
			particle.vel.x = -absf(particle.vel.x)
	if particle.pos.y < 0.0:
		particle.pos.y = 0.0
		if particle.has("vel"):
			particle.vel.y = absf(particle.vel.y)
	elif particle.pos.y > size.y:
		particle.pos.y = size.y
		if particle.has("vel"):
			particle.vel.y = -absf(particle.vel.y)

## Draws a generated sprite, rotated if given a nonzero angle. Uses
## draw_set_transform and resets it immediately after, since Godot's
## immediate-mode transform state persists across draw calls within the
## same _draw().
func _draw_sprite(texture: Texture2D, pos: Vector2, draw_size: Vector2, rotation: float) -> void:
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-draw_size / 2.0, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Fish get a two-piece draw instead of _draw_sprite: a rigid body (no
## wobble, rotates only with the overall heading) and a tail cropped from
## the same source image (see FISH_TAIL_FRACTION / FISH_TAIL_AT_TOP),
## rotated around the seam where it joins the body. That's what makes
## only the tail wag instead of the whole fish rocking - no second image
## needed, just draw_texture_rect_region on two sub-rects of one texture.
func _draw_fish(f: Dictionary) -> void:
	var base_rotation: float = f.vel.angle() + FISH_FACING_OFFSET
	var wobble: float = sin(f.wobble_phase) * FISH_WOBBLE_AMPLITUDE

	# grow_scale (see _resize_to_population) makes a fractional-population
	# "budding" fish render smaller than a fully-born one - same idea as
	# DAPHNIA_SPRITE_SIZE * _daphnia_size_scale below, just computed
	# per-instance here since _draw_fish only gets one Dictionary argument.
	var sprite_size: Vector2 = FISH_SPRITE_SIZE * float(f.get("grow_scale", 1.0))

	var tex_size := FISH_TEXTURE.get_size()
	var tail_src_height := tex_size.y * FISH_TAIL_FRACTION
	var tail_local_height := sprite_size.y * FISH_TAIL_FRACTION
	var body_local_height := sprite_size.y - tail_local_height
	var half_height := sprite_size.y / 2.0
	var half_width := sprite_size.x / 2.0

	var body_src: Rect2
	var tail_src: Rect2
	var body_dest: Rect2
	var tail_dest: Rect2
	var seam_local_y: float

	if FISH_TAIL_AT_TOP:
		tail_src = Rect2(Vector2.ZERO, Vector2(tex_size.x, tail_src_height))
		body_src = Rect2(Vector2(0.0, tail_src_height), Vector2(tex_size.x, tex_size.y - tail_src_height))
		seam_local_y = -half_height + tail_local_height
		body_dest = Rect2(Vector2(-half_width, seam_local_y), Vector2(sprite_size.x, body_local_height))
		tail_dest = Rect2(Vector2(-half_width, -tail_local_height), Vector2(sprite_size.x, tail_local_height))
	else:
		body_src = Rect2(Vector2.ZERO, Vector2(tex_size.x, tex_size.y - tail_src_height))
		tail_src = Rect2(Vector2(0.0, tex_size.y - tail_src_height), Vector2(tex_size.x, tail_src_height))
		seam_local_y = half_height - tail_local_height
		body_dest = Rect2(Vector2(-half_width, -half_height), Vector2(sprite_size.x, body_local_height))
		tail_dest = Rect2(Vector2(-half_width, 0.0), Vector2(sprite_size.x, tail_local_height))

	draw_set_transform(f.pos, base_rotation, Vector2.ONE)
	draw_texture_rect_region(FISH_TEXTURE, body_dest, body_src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var seam_world: Vector2 = f.pos + Vector2(0, seam_local_y).rotated(base_rotation)
	draw_set_transform(seam_world, base_rotation + wobble, Vector2.ONE)
	_draw_fish_tail_feathered(tail_dest, tail_src, not FISH_TAIL_AT_TOP)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The tail is rotated by `wobble` relative to the body (see _draw_fish),
## so the source artwork's own spine highlight no longer lines up across
## the crop boundary whenever wobble is nonzero - confirmed by cropping and
## magnifying a captured frame (not visible at normal gameplay zoom, but
## real). Rather than one hard-edged draw, split the tail into thin strips
## along its length and fade the strips nearest the seam toward
## transparent, so the body underneath (drawn first, unrotated) shows
## through the blend zone instead of a visible mismatch. No shader and no
## new art needed - just several draw_texture_rect_region calls with
## graduated alpha. `proximal_at_start` says whether the seam end of
## tail_dest/tail_src is at their local offset 0 or their far end, which
## flips between the FISH_TAIL_AT_TOP branches in _draw_fish.
func _draw_fish_tail_feathered(tail_dest: Rect2, tail_src: Rect2, proximal_at_start: bool) -> void:
	for i in FISH_TAIL_SEAM_FEATHER_STEPS:
		var t0 := float(i) / float(FISH_TAIL_SEAM_FEATHER_STEPS)
		var t1 := float(i + 1) / float(FISH_TAIL_SEAM_FEATHER_STEPS)
		var off0 := t0 if proximal_at_start else (1.0 - t0)
		var off1 := t1 if proximal_at_start else (1.0 - t1)
		var lo := minf(off0, off1)
		var hi := maxf(off0, off1)

		var strip_dest := Rect2(tail_dest.position + Vector2(0.0, tail_dest.size.y * lo), Vector2(tail_dest.size.x, tail_dest.size.y * (hi - lo)))
		var strip_src := Rect2(tail_src.position + Vector2(0.0, tail_src.size.y * lo), Vector2(tail_src.size.x, tail_src.size.y * (hi - lo)))

		var mid_t := (t0 + t1) * 0.5
		var alpha := 1.0 if mid_t >= FISH_TAIL_SEAM_FEATHER_FRACTION else lerpf(FISH_TAIL_SEAM_MIN_ALPHA, 1.0, mid_t / FISH_TAIL_SEAM_FEATHER_FRACTION)
		draw_texture_rect_region(FISH_TEXTURE, strip_dest, strip_src, Color(1.0, 1.0, 1.0, alpha))

func _draw() -> void:
	# Nutrient load (§7) as water tint, drawn first so it sits over the
	# background but under every creature - a murkier wash at high nutrient
	# load rather than a number, per §7's "diagnose by looking."
	_draw_nutrient_tint()

	# Floor decorations first - rocks rest on the pond bottom, underneath
	# everything that swims.
	for r in _rocks:
		_draw_sprite(r.texture, r.pos, Vector2(r.size, r.size), r.rotation)

	for s in _silt:
		var radius: float = lerpf(0.8, 2.2, s.depth)
		var color := Color(0.85, 0.87, 0.8, lerpf(0.15, 0.4, s.depth))
		draw_circle(s.pos, radius, color)

	for a in _algae:
		_draw_sprite(ALGAE_TEXTURE, a.pos, ALGAE_SPRITE_SIZE * float(a.get("grow_scale", 1.0)), 0.0)
	for d in _daphnia:
		_draw_sprite(DAPHNIA_TEXTURE, d.pos, DAPHNIA_SPRITE_SIZE * _daphnia_size_scale * float(d.get("grow_scale", 1.0)), d.facing.angle() + DAPHNIA_FACING_OFFSET)
	for f in _fish:
		_draw_fish(f)

	# Lily pads float on the surface, above the swimming creatures.
	for p in _lilypads:
		var wobble := sin(p.sway_phase) * 0.06
		_draw_sprite(p.texture, p.pos, Vector2(p.size, p.size), p.base_rotation + wobble)

	for p in _pops:
		var t: float = p.age / POP_DURATION
		var color: Color = p.color
		color.a = 1.0 - t
		draw_circle(p.pos, lerpf(2.0, 14.0, t), color)

	_draw_capacity_gauge()
	_draw_collapse_flash()
	_draw_numeric_overlay()

## Nutrient load (§7) - a full-scene translucent wash rather than a
## readout. Scales toward NUTRIENT_TINT_MAX_ALPHA as nutrients approach
## NUTRIENT_TINT_REFERENCE_LEVEL, using the same log-normalized shape as
## _population_to_count so it saturates gracefully rather than clipping.
func _draw_nutrient_tint() -> void:
	if _last_state == null:
		return
	var t := clampf(log(maxf(_last_state.nutrients, 0.0) + 1.0) / log(NUTRIENT_TINT_REFERENCE_LEVEL + 1.0), 0.0, 1.0)
	var color := NUTRIENT_TINT_COLOR
	color.a = t * NUTRIENT_TINT_MAX_ALPHA
	draw_rect(Rect2(Vector2.ZERO, size), color)

## Capacity (§6.3) as a glowing orb rather than a number - fits the
## existing "bioluminescent" art direction better than a bar or dial would.
## Both radius and brightness grow with capacity, saturating near
## CAPACITY_GAUGE_REFERENCE_LEVEL.
func _draw_capacity_gauge() -> void:
	if _last_state == null:
		return
	var t := clampf(log(maxf(_last_state.capacity, 0.0) + 1.0) / log(CAPACITY_GAUGE_REFERENCE_LEVEL + 1.0), 0.0, 1.0)
	var radius := lerpf(CAPACITY_GAUGE_MIN_RADIUS, CAPACITY_GAUGE_MAX_RADIUS, t)
	var glow := CAPACITY_GAUGE_COLOR
	glow.a = lerpf(0.35, 0.9, t)
	draw_circle(CAPACITY_GAUGE_POSITION, radius * 1.6, Color(glow.r, glow.g, glow.b, glow.a * 0.35))
	draw_circle(CAPACITY_GAUGE_POSITION, radius, glow)

## A collapse (§1 pillar 3) is a real, sudden event - "a story, not a game
## over" only reads that way if the player can tell something happened, so
## it gets a brief full-pond flash rather than being invisible outside the
## debug chart's line graph.
func _draw_collapse_flash() -> void:
	if _collapse_flash_timer <= 0.0:
		return
	var t := _collapse_flash_timer / COLLAPSE_FLASH_DURATION
	var color := COLLAPSE_FLASH_COLOR
	color.a = t * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), color)

## Playtesting needs the real numbers, not just the visual gauges above -
## see NUMERIC_OVERLAY_ENABLED and the top-of-file docstring. Drawn last so
## it's readable over everything else, including the nutrient tint/
## collapse flash.
func _draw_numeric_overlay() -> void:
	if not NUMERIC_OVERLAY_ENABLED or _last_state == null:
		return
	var s = _last_state
	var lines := [
		"algae=%.2f  daphnia=%.2f (mean_size=%.2f)  fish=%.2f" % [s.algae, s.daphnia, s.daphnia_mean_size, s.fish],
		"nutrients=%.2f  detritus=%.2f  capacity=%.2f  collapses=%d  pace=%.2fx" % [
			s.nutrients, s.detritus, s.capacity, s.collapse_count, _sim.get_pace_scale()
		],
	]
	var y := int(size.y) - 44
	for line in lines:
		draw_string(ThemeDB.fallback_font, Vector2(8, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		y += 20
