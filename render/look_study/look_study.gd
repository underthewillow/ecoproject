extends Control

## Track B Phase B1/B2 - motion + look study (§7.1, §8). Fake sine-wave
## population counts stand in for real sim state - the renderer only ever
## needs counts, which is exactly why this can run independent of how far
## Track A has gotten.
##
## Full pixel-art commitment: this Control renders inside a low-res
## SubViewport (see look_study.tscn - 288x162, nearest-neighbor upscaled
## 4x to fill the window), and organisms are drawn as PixelLab-generated
## sprites instead of flat circles. REFERENCE_WIDTH lets the motion
## constants below (tuned by feel against the old 1152px-wide full-window
## canvas) keep the same relative-to-canvas feel at the new, smaller
## internal resolution, rather than needing every constant hand-recomputed.
##
## Predation is cosmetic-only here too: daphnia bias their hops toward the
## nearest algae in range, fish bias their darts toward the nearest
## daphnia, and "eating" just respawns the prey particle elsewhere with a
## brief flash. Nothing here talks to the real sim - it's testing whether
## predator/prey interaction reads as such by eye, same as the rest of
## Track B.

const ALGAE_TEXTURE := preload("res://render/sprites/algae.png")
const DAPHNIA_TEXTURE := preload("res://render/sprites/daphnia.png")
const FISH_TEXTURE := preload("res://render/sprites/fish.png")

const ALGAE_SPRITE_SIZE := Vector2(8, 8)
const DAPHNIA_SPRITE_SIZE := Vector2(10, 10)
const FISH_SPRITE_SIZE := Vector2(18, 11)

const ALGAE_COLOR := Color.LIME_GREEN
const DAPHNIA_COLOR := Color.GOLD
const FISH_COLOR := Color.ORCHID
const SILT_COLOR := Color(0.75, 0.78, 0.72)

## Matches water_background.gdshader's shallow/deep colors, so organisms
## blend into the same fog rather than floating on top of it as flat,
## disconnected UI dots.
const SHALLOW_WATER_COLOR := Color(0.07, 0.20, 0.24)
const DEEP_WATER_COLOR := Color(0.01, 0.05, 0.09)

const ALGAE_MAX_PARTICLES := 150
const DAPHNIA_MAX_PARTICLES := 60
const FISH_MAX_PARTICLES := 10

## The canvas these motion constants were tuned against (§8's Phase B1
## calming pass) before the low-res SubViewport shrank the actual working
## canvas to 288px wide. Everything distance/speed-related below is
## multiplied by _scale so the motion keeps the same feel relative to
## canvas size instead of suddenly looking ~4x faster.
const REFERENCE_WIDTH := 1152.0

const DAPHNIA_HOP_STRENGTH := 55.0
const DAPHNIA_DAMPING := 8.0
const DAPHNIA_SINK_SPEED := 4.0
const DAPHNIA_DETECT_RADIUS := 70.0
const DAPHNIA_EAT_RADIUS := 6.0
const DAPHNIA_EAT_COOLDOWN := 1.2

const FISH_GLIDE_SPEED := 18.0
const FISH_DART_SPEED := 65.0
const FISH_DETECT_RADIUS := 90.0
const FISH_EAT_RADIUS := 10.0
const FISH_EAT_COOLDOWN := 2.0

const POP_DURATION := 0.5

## Silt is pure atmosphere (§8's Phase B2 checklist), not a species - a
## fixed count, no population target, no interaction with anything else.
const SILT_COUNT := 40

var _scale := 1.0
var _time := 0.0
var _algae: Array[Dictionary] = []
var _daphnia: Array[Dictionary] = []
var _fish: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _silt: Array[Dictionary] = []

func _ready() -> void:
	randomize()  # cosmetic layer only - no determinism requirement here, unlike the sim's seeded RNG
	_scale = size.x / REFERENCE_WIDTH
	for i in SILT_COUNT:
		_silt.append(_spawn_silt())

func _process(delta: float) -> void:
	_time += delta
	_update_population_targets()
	_step_algae(delta)
	_step_daphnia(delta)
	_step_fish(delta)
	_step_pops(delta)
	_step_silt(delta)
	queue_redraw()

## Log-scaled, hard-capped mapping from a (fake) population number to a
## particle count (§4.1) - the same pipeline the real sim drives at
## Phase 6, just fed a sine wave here instead of a snapshot.
func _update_population_targets() -> void:
	_resize(_algae, _fake_population_to_count(40.0, 0.05, 0.0, ALGAE_MAX_PARTICLES), _spawn_algae)
	_resize(_daphnia, _fake_population_to_count(20.0, 0.11, 2.0, DAPHNIA_MAX_PARTICLES), _spawn_daphnia)
	_resize(_fish, _fake_population_to_count(5.0, 0.04, 4.5, FISH_MAX_PARTICLES), _spawn_fish)

func _fake_population_to_count(amplitude: float, freq: float, phase: float, max_particles: int) -> int:
	var raw_population := amplitude * (1.0 + sin(_time * freq + phase))
	var scaled := log(raw_population + 1.0) * 8.0
	return clampi(int(scaled), 0, max_particles)

func _resize(list: Array[Dictionary], target_count: int, spawn_fn: Callable) -> void:
	while list.size() < target_count:
		list.append(spawn_fn.call())
	while list.size() > target_count:
		list.pop_back()

func _spawn_algae() -> Dictionary:
	return {"pos": _random_position(), "drift_phase": randf() * TAU}

func _spawn_daphnia() -> Dictionary:
	return {"pos": _random_position(), "vel": Vector2.ZERO, "hop_timer": randf_range(0.6, 2.2), "eat_cooldown": 0.0}

func _spawn_fish() -> Dictionary:
	var angle := randf() * TAU
	return {"pos": _random_position(), "vel": Vector2.RIGHT.rotated(angle) * FISH_GLIDE_SPEED * _scale, "dart_timer": randf_range(4.0, 9.0), "eat_cooldown": 0.0}

## depth is a purely cosmetic 0-1 value (near 1 = shallow/bright/bigger,
## near 0 = deep/dim/smaller) - a cheap depth cue independent of the
## background shader's own depth fog.
func _spawn_silt() -> Dictionary:
	return {"pos": _random_position(), "drift_phase": randf() * TAU, "depth": randf()}

func _random_position() -> Vector2:
	return Vector2(randf() * size.x, randf() * size.y)

## Algae has no agency (§7.1) - it drifts on a slow, shared current plus a
## little per-particle wobble, never a direction of its own choosing, and
## never reacts to being hunted. Getting eaten just means some daphnia
## replaced it with a fresh one elsewhere (see _try_eat).
func _step_algae(delta: float) -> void:
	var current := Vector2(sin(_time * 0.08), cos(_time * 0.05)) * 4.0 * _scale
	for a in _algae:
		a.drift_phase += delta * 0.35
		var wobble := Vector2(sin(a.drift_phase), cos(a.drift_phase * 1.3)) * 2.0 * _scale
		a.pos += (current + wobble) * delta
		_contain(a)

## Silt drifts even more passively than algae (§7.1's spirit extended to
## ambient debris) - slower current, no wobble bias toward anything, and
## never interacts with predation or population counts.
func _step_silt(delta: float) -> void:
	var current := Vector2(sin(_time * 0.05), cos(_time * 0.04)) * 2.0 * _scale
	for s in _silt:
		s.drift_phase += delta * 0.2
		var wobble := Vector2(sin(s.drift_phase), cos(s.drift_phase * 0.7)) * 1.0 * _scale
		s.pos += (current + wobble) * delta * (0.4 + s.depth * 0.6)
		_contain(s)

## Daphnia hop and jerk (§7.1) - discrete, erratic vertical bursts, not
## smooth drift. Hops bias toward the nearest algae in range (still with
## some randomness and the upward jerk mixed in, so it stays jerky rather
## than reading as a smart chase), and eating just triggers when close.
func _step_daphnia(delta: float) -> void:
	var hop_strength := DAPHNIA_HOP_STRENGTH * _scale
	var detect_radius := DAPHNIA_DETECT_RADIUS * _scale
	var eat_radius := DAPHNIA_EAT_RADIUS * _scale
	for d in _daphnia:
		d.hop_timer -= delta
		d.eat_cooldown = maxf(d.eat_cooldown - delta, 0.0)
		if d.hop_timer <= 0.0:
			d.hop_timer = randf_range(0.6, 2.2)
			var target_index := _find_nearest(d.pos, _algae, detect_radius)
			var direction: Vector2
			if target_index >= 0:
				direction = (_algae[target_index].pos - d.pos).normalized()
				direction.y -= 0.3  # keep some of the characteristic upward jerk even while chasing
				direction = direction.normalized()
			else:
				direction = Vector2(randf_range(-0.4, 0.4), -1.0).normalized()
			d.vel = direction * hop_strength * randf_range(0.6, 1.2)
		d.vel = d.vel.move_toward(Vector2.ZERO, DAPHNIA_DAMPING * hop_strength * delta)
		d.pos += d.vel * delta
		d.pos.y += DAPHNIA_SINK_SPEED * _scale * delta
		_contain(d)
		if d.eat_cooldown <= 0.0 and _try_eat(d, _algae, eat_radius, ALGAE_COLOR, _spawn_algae):
			d.eat_cooldown = DAPHNIA_EAT_COOLDOWN

## Fish glide, then dart (§7.1) - long low-effort coasting punctuated by
## sudden acceleration. Darts aim at the nearest daphnia in range when one
## exists, otherwise a random turn, keeping the same glide/dart rhythm
## either way.
func _step_fish(delta: float) -> void:
	var glide_speed := FISH_GLIDE_SPEED * _scale
	var dart_speed := FISH_DART_SPEED * _scale
	var detect_radius := FISH_DETECT_RADIUS * _scale
	var eat_radius := FISH_EAT_RADIUS * _scale
	for f in _fish:
		f.dart_timer -= delta
		f.eat_cooldown = maxf(f.eat_cooldown - delta, 0.0)
		if f.dart_timer <= 0.0:
			f.dart_timer = randf_range(4.0, 9.0)
			var target_index := _find_nearest(f.pos, _daphnia, detect_radius)
			if target_index >= 0:
				f.vel = (_daphnia[target_index].pos - f.pos).normalized() * dart_speed
			else:
				var turn := randf_range(-1.2, 1.2)
				f.vel = f.vel.rotated(turn).normalized() * dart_speed
		# Glide decay is much gentler than the dart itself, so most of a
		# fish's time reads as coasting, not accelerating.
		f.vel = f.vel.move_toward(f.vel.normalized() * glide_speed, glide_speed * 0.4 * delta)
		f.pos += f.vel * delta
		_contain(f)
		if f.eat_cooldown <= 0.0 and _try_eat(f, _daphnia, eat_radius, DAPHNIA_COLOR, _spawn_daphnia):
			f.eat_cooldown = FISH_EAT_COOLDOWN

## "Eating" is purely cosmetic: the nearest prey within eat_radius gets
## replaced by a freshly spawned one elsewhere, so the population count
## stays exactly what _update_population_targets says it should be - only
## individual identity changes, which is all the eye can tell apart anyway.
## Gated by a per-predator cooldown (see callers) so eating reads as
## discrete events instead of a constant strobe of flashes.
func _try_eat(eater: Dictionary, prey_list: Array[Dictionary], eat_radius: float, pop_color: Color, respawn_fn: Callable) -> bool:
	var idx := _find_nearest(eater.pos, prey_list, eat_radius)
	if idx >= 0:
		_pops.append({"pos": prey_list[idx].pos, "color": pop_color, "age": 0.0})
		prey_list[idx] = respawn_fn.call()
		return true
	return false

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

## Blends a base color toward the ambient water color by depth (y position,
## same convention as the background shader's fog: top = shallow, bottom =
## deep), so an organism near the bottom looks like it's sitting inside
## the murk instead of drawn on top of it in an unrelated flat color.
func _depth_tint(base_color: Color, pos: Vector2) -> Color:
	var depth_t := clampf(pos.y / size.y, 0.0, 1.0)
	var water_tint := SHALLOW_WATER_COLOR.lerp(DEEP_WATER_COLOR, depth_t)
	return base_color.lerp(water_tint, depth_t * 0.5)

## Cheap stand-in for the background shader's caustic_pattern (not an
## exact match, just visually consistent) so organisms passing through a
## bright patch of "light" pick up a bit of extra glow, tying them into
## the same lighting the water itself is showing.
func _shimmer(pos: Vector2) -> float:
	var uv := pos / size
	var t := _time * 0.3
	var v := sin(uv.x * 20.0 + t * 3.0) * sin(uv.y * 20.0 - t * 2.4)
	return clampf(absf(v), 0.0, 1.0)

## Draws a PixelLab sprite tinted by depth/shimmer (see above) instead of
## a flat circle, so organisms read as actual pixel-art creatures. Uses
## draw_set_transform for rotation (fish only - algae/daphnia pass 0) and
## resets it immediately after, since Godot's immediate-mode transform
## state persists across draw calls within the same _draw().
func _draw_sprite(texture: Texture2D, pos: Vector2, draw_size: Vector2, rotation: float, base_color: Color) -> void:
	var color := _depth_tint(base_color, pos)
	color = color.lightened(_shimmer(pos) * 0.3)
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-draw_size / 2.0, draw_size), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	for s in _silt:
		var radius: float = lerpf(0.8, 2.2, s.depth) * _scale
		var color := SILT_COLOR
		color.a = lerpf(0.15, 0.4, s.depth)
		draw_circle(s.pos, radius, color)
	for a in _algae:
		_draw_sprite(ALGAE_TEXTURE, a.pos, ALGAE_SPRITE_SIZE, 0.0, ALGAE_COLOR)
	for d in _daphnia:
		_draw_sprite(DAPHNIA_TEXTURE, d.pos, DAPHNIA_SPRITE_SIZE, 0.0, DAPHNIA_COLOR)
	for f in _fish:
		_draw_sprite(FISH_TEXTURE, f.pos, FISH_SPRITE_SIZE, f.vel.angle(), FISH_COLOR)
	for p in _pops:
		var t: float = p.age / POP_DURATION
		var color: Color = p.color
		color.a = 1.0 - t
		draw_circle(p.pos, lerpf(2.0, 14.0, t) * _scale, color)

	draw_string(ThemeDB.fallback_font, Vector2(4, 10),
		"algae=%d daphnia=%d fish=%d" % [_algae.size(), _daphnia.size(), _fish.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
