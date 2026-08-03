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
## nutrients) and the difficulty toggle. Direct feedback split these into
## two deliberately different presentation styles rather than one:
##
## - The POND ITSELF (this script's _draw(), inside PondViewport) carries
##   only effects that are arguably part of the water/scene, not UI chrome:
##   nutrient load as a water tint, detritus as silt density, a collapse as
##   a full-pond flash. Nothing else draws on top of it - no buttons, no
##   numbers, no gauges.
## - A separate SIDE PANEL (look_study.tscn's %SidePanel, built by
##   _build_ui() below) holds everything actionable: one card per species
##   (icon, population gauge bar, Introduce button), gauge bars for
##   capacity/nutrients/detritus/daphnia mean size, the nutrient-amount
##   control, and the difficulty buttons. §7's "numbers stay hidden by
##   default" is still the long-term intent, but direct playtesting
##   feedback was that the numbers are needed *right now* to judge whether
##   any of this is tuned sensibly - see NUMERIC_LABELS_ENABLED: the raw
##   values are shown as text next to each bar too, meant to come back off
##   once there's enough played experience to trust the bars alone.
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

## Side panel gauge-bar fill colors (§ redesign: research on game-UI
## color coding recommends each resource read as consistently the same
## color everywhere it appears, and reserving distinct hues for things the
## player actually acts on/watches). Algae/daphnia/fish reuse their
## existing pond particle colors so the panel and the pond agree visually.
## Capacity reuses the "bioluminescent" glow color from the removed orb
## gauge it replaced, so that association carries over. Nutrients/detritus
## are brighter variants of their pond-tint colors (the tint colors
## themselves are too dark/desaturated to read well as a bar fill against
## the panel background). Daphnia mean size gets its own distinct hue since
## it's a different kind of thing - a trait/evolution signal, not a count.
const PANEL_BACKGROUND_COLOR := Color(0.07, 0.11, 0.12, 0.97)
const ALGAE_GAUGE_COLOR := ALGAE_POP_COLOR
const DAPHNIA_GAUGE_COLOR := DAPHNIA_POP_COLOR
const FISH_GAUGE_COLOR := FISH_POP_COLOR
const CAPACITY_GAUGE_COLOR := Color(0.6, 0.95, 0.85)
const NUTRIENTS_GAUGE_COLOR := Color(0.78, 0.72, 0.35)
const DETRITUS_GAUGE_COLOR := Color(0.62, 0.56, 0.46)
const DAPHNIA_SIZE_GAUGE_COLOR := Color(0.82, 0.6, 0.88)
const GAUGE_TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.35)

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
## meant to read as "how murky/silty," not as a literal count. Its
## reference level is declared further down alongside the other gauge-bar
## maximums, since it now does double duty as the side panel's detritus bar
## max too.

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
## to false once the panel's gauge bars alone are trusted.
const NUMERIC_LABELS_ENABLED := true

## Daphnia's rendered size follows the real evolutionary signal (§4.2) -
## sim_config.gd's daphnia_reference_size (1.0) is the sprite's designed
## scale, and daphnia_size_min/max (0.5/2.0) is the full trait range; this
## clamps the visual range slightly inside that so it never reads as
## vanishingly tiny or absurdly oversized on screen.
const DAPHNIA_REFERENCE_TRAIT_SIZE := 1.0
const DAPHNIA_VISUAL_SIZE_SCALE_RANGE := Vector2(0.5, 1.8)

## Gauge-bar maximums for the side panel (see _build_ui/_update_panel).
## Algae reuses sim_config.gd's own carrying capacity (a real ceiling,
## fetched dynamically via _sim.get_algae_carrying_capacity() - not a
## constant here); daphnia/fish/nutrients/detritus/capacity have no
## equivalent hard cap, so these are hand-picked "reads as full" reference
## levels, same caveat as everything else calibrated by feel in Phase 5/6.
const DAPHNIA_GAUGE_MAX_POPULATION := 20.0
const FISH_GAUGE_MAX_POPULATION := 5.0
const NUTRIENT_TINT_REFERENCE_LEVEL := 25.0  # also the nutrient gauge bar's max - one number, two uses
## Recalibrated against a real recorded session (see docs/audio-design-notes.md's UI review
## entry): detritus held 25-45 for the whole clip, well above the old reference of 15, which
## pegged the bar visually full for the entire session with no headroom to show it still
## climbing; capacity held 2-16 the whole time against a max of 200, which made the bar read
## as almost perpetually empty. Both defeated the redesign's "gauge should read as alive at a
## glance" goal. Still a by-feel estimate, not a hard sim ceiling - may need another pass once
## there's a longer/higher-population session to calibrate against.
const DETRITUS_REFERENCE_LEVEL := 50.0  # also the detritus gauge bar's max
const CAPACITY_GAUGE_MAX := 40.0

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

## A founder introduction pops new individuals into an existing,
## already-moving population with zero visual distinction from anything
## already there - direct feedback was that this reads as "positions
## changing," since there's no way to tell a brand new individual apart
## from an existing one that simply drifted/hopped/glided on its own (see
## _apply_population_jump). A quick grow-in plus a ripple at the spawn
## point (real drop-in-water reads: a ring expanding from a point) gives
## the new arrival an obvious, trackable "this one just appeared here"
## moment instead.
const INTRODUCTION_START_SCALE := 0.1
const INTRODUCTION_GROW_TIME := 0.35
const RIPPLE_DURATION := 0.9
const RIPPLE_MIN_RADIUS := 3.0
const RIPPLE_MAX_RADIUS := 24.0
const RIPPLE_LINE_WIDTH := 1.6
const RIPPLE_COLOR := Color(0.85, 0.95, 1.0, 0.6)
## Two concentric rings per drop (the second starts RIPPLE_RING_DELAY
## later) reads more like an actual water ripple than a single ring.
const RIPPLE_RING_DELAY := 0.15

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
var _ripples: Array[Dictionary] = []
var _silt: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _lilypads: Array[Dictionary] = []

var _introduction_sfx: AudioStreamPlayer

var _founder_spin: SpinBox
var _nutrient_spin: SpinBox
var _algae_button: Button
var _daphnia_button: Button
var _fish_button: Button
var _nutrient_button: Button

## Species gauge bars + value labels (one card each, see _make_species_card).
var _algae_bar: ProgressBar
var _algae_value_label: Label
var _daphnia_bar: ProgressBar
var _daphnia_value_label: Label
var _fish_bar: ProgressBar
var _fish_value_label: Label

## Metric gauge bars + value labels (see _make_metric_row).
var _capacity_bar: ProgressBar
var _capacity_value_label: Label
var _nutrients_bar: ProgressBar
var _nutrients_value_label: Label
var _detritus_bar: ProgressBar
var _detritus_value_label: Label
var _daphnia_size_bar: ProgressBar
var _daphnia_size_value_label: Label
var _collapse_count_label: Label

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
	_introduction_sfx = $IntroductionSfx
	_build_ui()

## The two player verbs (§6) plus every gauge, built into %SidePanel (see
## look_study.tscn) rather than this node - direct feedback was that the
## pond itself should carry no UI chrome at all, buttons and gauges
## included, and belongs in a panel separate from the water. This node
## (Particles) still owns the SimCore and all the game logic; it just
## reaches sideways into a sibling Control to place the UI, rather than
## parenting it onto itself the way an earlier pass did (which drew
## directly on top of the pond).
##
## Redesigned after direct feedback on a first pass that required
## scrolling in both directions to reach lower controls and buried
## capacity (the resource spent on every action) near the bottom.
## Research on game HUD/resource-panel conventions (hierarchy by
## importance/urgency, single-glance readability, consistent color coding
## per resource) informed the fixes: capacity now leads the panel; every
## species/metric is a single compact row (icon or label, a colored gauge
## bar, the current value, and - for species - a small "+" button) instead
## of stacked header/bar/button blocks, which is what actually caused the
## vertical overflow; and there is deliberately no ScrollContainer at all
## - the compact rows are meant to always fit without one.
func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BACKGROUND_COLOR
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	%SidePanel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	%SidePanel.add_child(content)

	# Capacity leads the panel (hierarchy by importance: it's spent on
	# every action, so it gets the most prominent position and a taller
	# bar than the read-only metrics further down).
	var capacity_metric := _make_metric_row("Capacity", CAPACITY_GAUGE_COLOR, 22.0)
	content.add_child(capacity_metric.root)
	_capacity_bar = capacity_metric.bar
	_capacity_value_label = capacity_metric.value_label

	content.add_child(HSeparator.new())

	var difficulty_group := ButtonGroup.new()
	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 4)
	content.add_child(difficulty_row)
	var challenging_btn := _make_toggle_button("Challenging", difficulty_group, func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CHALLENGING]))
	var casual_btn := _make_toggle_button("Casual", difficulty_group, func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.CASUAL]))
	var relaxing_btn := _make_toggle_button("Relaxing", difficulty_group, func(): _sim.set_pace_scale(SimConfig.PACE_SCALE_BY_DIFFICULTY[SimConfig.Difficulty.RELAXING]))
	challenging_btn.button_pressed = true  # matches the actual startup default (pace_scale=1.0) - the toggle state itself is the pace readout now, no separate label needed
	difficulty_row.add_child(challenging_btn)
	difficulty_row.add_child(casual_btn)
	difficulty_row.add_child(relaxing_btn)

	var founder_row := HBoxContainer.new()
	content.add_child(founder_row)
	var founder_label := _make_label("Founder count")
	founder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	founder_row.add_child(founder_label)
	_founder_spin = SpinBox.new()
	_founder_spin.min_value = 0.5
	_founder_spin.max_value = 50.0
	_founder_spin.step = 0.5
	_founder_spin.value = FOUNDER_DEFAULT
	_founder_spin.custom_minimum_size = Vector2(64, 0)
	founder_row.add_child(_founder_spin)

	content.add_child(HSeparator.new())

	var algae_card := _make_species_card(ALGAE_TEXTURE, "Algae", ALGAE_GAUGE_COLOR, func(): _sim.introduce_species("algae", _founder_spin.value))
	content.add_child(algae_card.root)
	_algae_bar = algae_card.bar
	_algae_value_label = algae_card.value_label
	_algae_button = algae_card.button

	var daphnia_card := _make_species_card(DAPHNIA_TEXTURE, "Daphnia", DAPHNIA_GAUGE_COLOR, func(): _sim.introduce_species("daphnia", _founder_spin.value))
	content.add_child(daphnia_card.root)
	_daphnia_bar = daphnia_card.bar
	_daphnia_value_label = daphnia_card.value_label
	_daphnia_button = daphnia_card.button

	var fish_card := _make_species_card(FISH_TEXTURE, "Fish", FISH_GAUGE_COLOR, func(): _sim.introduce_species("fish", _founder_spin.value))
	content.add_child(fish_card.root)
	_fish_bar = fish_card.bar
	_fish_value_label = fish_card.value_label
	_fish_button = fish_card.button

	content.add_child(HSeparator.new())

	var nutrients_metric := _make_metric_row("Nutrients", NUTRIENTS_GAUGE_COLOR)
	content.add_child(nutrients_metric.root)
	_nutrients_bar = nutrients_metric.bar
	_nutrients_value_label = nutrients_metric.value_label

	var nutrient_amount_row := HBoxContainer.new()
	content.add_child(nutrient_amount_row)
	var nutrient_amount_label := _make_label("Amount")
	nutrient_amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nutrient_amount_row.add_child(nutrient_amount_label)
	_nutrient_spin = SpinBox.new()
	_nutrient_spin.min_value = 0.5
	_nutrient_spin.max_value = 50.0
	_nutrient_spin.step = 0.5
	_nutrient_spin.value = NUTRIENT_AMOUNT_DEFAULT
	_nutrient_spin.custom_minimum_size = Vector2(64, 0)
	nutrient_amount_row.add_child(_nutrient_spin)
	_nutrient_button = _make_button("Add", func(): _sim.add_nutrients(_nutrient_spin.value))
	_nutrient_button.custom_minimum_size = Vector2(44, 0)
	nutrient_amount_row.add_child(_nutrient_button)

	var detritus_metric := _make_metric_row("Detritus", DETRITUS_GAUGE_COLOR)
	content.add_child(detritus_metric.root)
	_detritus_bar = detritus_metric.bar
	_detritus_value_label = detritus_metric.value_label

	var daphnia_size_metric := _make_metric_row("Daphnia size", DAPHNIA_SIZE_GAUGE_COLOR)
	content.add_child(daphnia_size_metric.root)
	_daphnia_size_bar = daphnia_size_metric.bar
	_daphnia_size_value_label = daphnia_size_metric.value_label

	content.add_child(HSeparator.new())
	_collapse_count_label = _make_label("Collapses: 0")
	content.add_child(_collapse_count_label)

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	return label

func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button

## Toggle-mode buttons sharing a ButtonGroup behave as a mutually-exclusive
## radio set - Godot handles the "only one pressed at a time" bookkeeping
## natively. Using the pressed/highlighted visual state to show which
## difficulty is active removes the need for a separate "Pace: Nx" label
## entirely, which is one whole row saved.
func _make_toggle_button(text: String, group: ButtonGroup, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(on_pressed)
	return button

## A colored, rounded gauge bar - see the const block above for why each
## resource gets its own consistent color rather than one default style.
func _make_gauge_bar(fill_color: Color, bar_height: float = 18.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, bar_height)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_style)

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = GAUGE_TRACK_COLOR
	track_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", track_style)

	return bar

## One self-contained row per species: icon, gauge, current value, and the
## Introduce button all on a single line - everything needed to read and
## act on one species stays together, and a single row (rather than a
## stacked header/bar/button block) is what actually keeps the panel from
## overflowing vertically. Returns the pieces the caller needs to keep
## updating.
func _make_species_card(texture: Texture2D, species_name: String, color: Color, on_introduce: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := _make_label(species_name)
	name_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(name_label)

	var bar := _make_gauge_bar(color)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var value_label := _make_label("")
	value_label.custom_minimum_size = Vector2(34, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var button := _make_button("+", on_introduce)
	button.custom_minimum_size = Vector2(26, 0)
	button.tooltip_text = "Introduce " + species_name
	row.add_child(button)

	return {"root": row, "bar": bar, "value_label": value_label, "button": button}

## A read-only gauge (no button) for a single metric - label, a colored
## bar, and the current value on one line. bar_height lets capacity render
## slightly taller than the rest (hierarchy by importance).
func _make_metric_row(label_text: String, color: Color, bar_height: float = 18.0) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := _make_label(label_text)
	label.custom_minimum_size = Vector2(74, 0)
	row.add_child(label)

	var bar := _make_gauge_bar(color, bar_height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var value_label := _make_label("")
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	return {"root": row, "bar": bar, "value_label": value_label}

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

## Refreshes every panel gauge/label from real state - called once per real
## sim tick (see _step_sim_ticks), not every render frame, since these
## values only change that often anyway.
func _update_panel(state) -> void:
	_set_gauge(_algae_bar, _algae_value_label, state.algae, _sim.get_algae_carrying_capacity())
	_set_gauge(_daphnia_bar, _daphnia_value_label, state.daphnia, DAPHNIA_GAUGE_MAX_POPULATION)
	_set_gauge(_fish_bar, _fish_value_label, state.fish, FISH_GAUGE_MAX_POPULATION)
	_set_gauge(_nutrients_bar, _nutrients_value_label, state.nutrients, NUTRIENT_TINT_REFERENCE_LEVEL)
	_set_gauge(_detritus_bar, _detritus_value_label, state.detritus, DETRITUS_REFERENCE_LEVEL)
	_set_gauge(_capacity_bar, _capacity_value_label, state.capacity, CAPACITY_GAUGE_MAX)

	var size_range: Vector2 = _sim.get_daphnia_size_range()
	_daphnia_size_bar.min_value = size_range.x
	_daphnia_size_bar.max_value = size_range.y
	_daphnia_size_bar.value = state.daphnia_mean_size
	_daphnia_size_value_label.text = ("%.2f" % state.daphnia_mean_size) if NUMERIC_LABELS_ENABLED else ""

	_collapse_count_label.text = "Collapses: %d" % state.collapse_count

func _set_gauge(bar: ProgressBar, value_label: Label, value: float, max_value: float) -> void:
	bar.min_value = 0.0
	bar.max_value = max_value
	bar.value = value
	value_label.text = ("%.2f" % value) if NUMERIC_LABELS_ENABLED else ""

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
	_step_ripples(delta)
	_step_introductions(_algae, delta)
	_step_introductions(_daphnia, delta)
	_step_introductions(_fish, delta)
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
	_update_panel(state)

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
		var spawned_any := false
		for i in new_count:
			if list.size() >= max_particles:
				break
			var entry: Dictionary = spawn_fn.call()
			# Starts small and grows into place over INTRODUCTION_GROW_TIME
			# (see _step_introductions) plus a ripple at its spawn point,
			# rather than popping in at full size indistinguishable from
			# everything already there.
			entry["grow_scale"] = INTRODUCTION_START_SCALE
			entry["introduction_age"] = 0.0
			list.append(entry)
			_spawn_ripple(entry.pos)
			spawned_any = true
		if spawned_any:
			_introduction_sfx.play()
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
	# If the eaten entry happened to be the one _resize_to_population is
	# tracking as the in-progress growth bud, a bare respawn_fn.call()
	# replacement (which carries no is_bud/grow_scale keys) silently
	# breaks that tracking: _find_bud_index() then finds nothing next
	# frame, _apply_smooth_growth miscounts plain_count as one too high,
	# removes an unrelated real individual to compensate, and spawns a
	# fresh bud elsewhere - visible as an unrelated individual vanishing
	# right as a new partial one appears, most noticeable right after a
	# founder introduction when the population is still small. Carrying
	# the bud markers over onto the replacement keeps the invariant intact.
	var replacement: Dictionary = respawn_fn.call()
	if prey_list[idx].get("is_bud", false):
		replacement["is_bud"] = true
		replacement["grow_scale"] = prey_list[idx].get("grow_scale", 1.0)
	prey_list[idx] = replacement
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

func _spawn_ripple(pos: Vector2) -> void:
	_ripples.append({"pos": pos, "age": 0.0})

func _step_ripples(delta: float) -> void:
	for r in _ripples:
		r.age += delta
	_ripples = _ripples.filter(func(r): return r.age < RIPPLE_DURATION + RIPPLE_RING_DELAY)

## Grows a freshly-introduced individual from INTRODUCTION_START_SCALE up
## to full size over INTRODUCTION_GROW_TIME - a separate mechanic from the
## growth-bud's grow_scale (§ _apply_smooth_growth), even though both
## ultimately drive the same field: a bud represents ongoing fractional
## reproduction and is tracked by identity (is_bud) across ticks, while an
## "introducing" entry is already a full, counted individual that's just
## playing a short pop-in animation once. Untagged (no "introduction_age"
## key) once it reaches full size, same as a bud loses "is_bud" once
## promoted.
func _step_introductions(list: Array[Dictionary], delta: float) -> void:
	for e in list:
		if not e.has("introduction_age"):
			continue
		e.introduction_age += delta
		var t: float = clampf(e.introduction_age / INTRODUCTION_GROW_TIME, 0.0, 1.0)
		e["grow_scale"] = lerpf(INTRODUCTION_START_SCALE, 1.0, t)
		if t >= 1.0:
			e.erase("introduction_age")

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

	# Drawn on top of everything else so a founder's ripple stays legible
	# even where it overlaps an existing creature - the whole point is
	# "look here, something just appeared," which a ripple hidden behind a
	# sprite wouldn't achieve.
	for r in _ripples:
		_draw_ripple_ring(r.pos, r.age)
		_draw_ripple_ring(r.pos, r.age - RIPPLE_RING_DELAY)

	_draw_collapse_flash()

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

## A collapse (§1 pillar 3) is a real, sudden event - "a story, not a game
## over" only reads that way if the player can tell something happened, so
## it gets a brief full-pond flash rather than being invisible outside the
## side panel's collapse counter. Kept on the pond itself (unlike the
## capacity/numeric readouts, which moved to %SidePanel) since it changes
## the water's own appearance rather than drawing UI chrome on top of it.
func _draw_collapse_flash() -> void:
	if _collapse_flash_timer <= 0.0:
		return
	var t := _collapse_flash_timer / COLLAPSE_FLASH_DURATION
	var color := COLLAPSE_FLASH_COLOR
	color.a = t * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), color)

## age < 0 means this ring hasn't started yet (see RIPPLE_RING_DELAY's
## second, staggered ring) - drawing nothing rather than clamping to 0
## keeps the two rings visibly offset instead of briefly overlapping at
## the same radius.
func _draw_ripple_ring(pos: Vector2, age: float) -> void:
	if age < 0.0 or age >= RIPPLE_DURATION:
		return
	var t := age / RIPPLE_DURATION
	var radius := lerpf(RIPPLE_MIN_RADIUS, RIPPLE_MAX_RADIUS, t)
	var color := RIPPLE_COLOR
	color.a *= 1.0 - t
	draw_arc(pos, radius, 0.0, TAU, 24, color, RIPPLE_LINE_WIDTH, true)
