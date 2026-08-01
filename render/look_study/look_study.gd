extends Control

## Track B look study (§7.1, §8) - top-down view, painterly/bioluminescent
## art direction. Fake sine-wave population counts stand in for real sim
## state - the renderer only ever needs counts, which is exactly why this
## can run independent of how far Track A has gotten.
##
## Background is now a single real illustration (render/water/
## pond_background.png), not a procedural shader or tiled texture. That
## sidesteps the whole class of tiling/seam/pulsing-sweep bugs from the
## earlier attempts: a background filling one fixed viewport doesn't need
## to tile at all. Creature/prop art is likewise generated (OpenAI
## gpt-image-1 via the media-pipeline MCP server), not flat shapes or
## pixel art - see git history for why both of those were dropped.
##
## Predation is cosmetic-only: daphnia bias their hops toward the nearest
## algae in range, fish bias their darts toward the nearest daphnia, and
## "eating" just respawns the prey particle elsewhere with a brief flash.
## Nothing here talks to the real sim.

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

## daphnia.png has its antennae pointing toward the top of the frame
## (confirmed by inspection) - same nose-up convention as the fish, so
## the same +90 degree offset applies.
const DAPHNIA_FACING_OFFSET := PI / 2.0

const ALGAE_POP_COLOR := Color(0.55, 0.85, 0.5)
const DAPHNIA_POP_COLOR := Color(0.75, 0.88, 0.95)
const FISH_POP_COLOR := Color(1.0, 0.72, 0.25)

const ALGAE_MAX_PARTICLES := 150
const DAPHNIA_MAX_PARTICLES := 60
const FISH_MAX_PARTICLES := 10

const DAPHNIA_HOP_STRENGTH := 65.0
const DAPHNIA_DAMPING := 8.0
const DAPHNIA_SINK_SPEED := 4.0
const DAPHNIA_DETECT_RADIUS := 140.0
const DAPHNIA_EAT_RADIUS := 16.0
const DAPHNIA_EAT_COOLDOWN := 1.2

const FISH_GLIDE_SPEED := 18.0
const FISH_DART_SPEED := 65.0
const FISH_DETECT_RADIUS := 90.0
const FISH_EAT_RADIUS := 16.0
const FISH_EAT_COOLDOWN := 2.0

const POP_DURATION := 0.5

## Silt is pure atmosphere, not a species - a fixed count, no population
## target, no interaction with anything else.
const SILT_COUNT := 40
const ROCK_COUNT := 4
const LILYPAD_COUNT := 5

var _time := 0.0
var _algae: Array[Dictionary] = []
var _daphnia: Array[Dictionary] = []
var _fish: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _silt: Array[Dictionary] = []
var _rocks: Array[Dictionary] = []
var _lilypads: Array[Dictionary] = []

func _ready() -> void:
	randomize()  # cosmetic layer only - no determinism requirement here, unlike the sim's seeded RNG
	for i in SILT_COUNT:
		_silt.append(_spawn_silt())
	for i in ROCK_COUNT:
		_rocks.append(_spawn_rock())
	for i in LILYPAD_COUNT:
		_lilypads.append(_spawn_lilypad())

func _process(delta: float) -> void:
	_time += delta
	_update_population_targets()
	_step_algae(delta)
	_step_daphnia(delta)
	_step_fish(delta)
	_step_pops(delta)
	_step_silt(delta)
	_step_lilypads(delta)
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
	var facing := Vector2.UP.rotated(randf() * TAU)
	return {"pos": _random_position(), "vel": Vector2.ZERO, "facing": facing, "hop_timer": randf_range(0.4, 1.4), "eat_cooldown": 0.0}

func _spawn_fish() -> Dictionary:
	var angle := randf() * TAU
	return {
		"pos": _random_position(),
		"vel": Vector2.RIGHT.rotated(angle) * FISH_GLIDE_SPEED,
		"dart_timer": randf_range(4.0, 9.0),
		"eat_cooldown": 0.0,
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
		d.eat_cooldown = maxf(d.eat_cooldown - delta, 0.0)
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
		if d.eat_cooldown <= 0.0 and _try_eat(d, _algae, DAPHNIA_EAT_RADIUS, ALGAE_POP_COLOR, _spawn_algae):
			d.eat_cooldown = DAPHNIA_EAT_COOLDOWN

## Fish glide, then dart (§7.1) - long low-effort coasting punctuated by
## sudden acceleration. Darts aim at the nearest daphnia in range when one
## exists, otherwise a random turn, keeping the same glide/dart rhythm
## either way.
func _step_fish(delta: float) -> void:
	for f in _fish:
		f.dart_timer -= delta
		f.eat_cooldown = maxf(f.eat_cooldown - delta, 0.0)
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
		if f.eat_cooldown <= 0.0 and _try_eat(f, _daphnia, FISH_EAT_RADIUS, DAPHNIA_POP_COLOR, _spawn_daphnia):
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

	var tex_size := FISH_TEXTURE.get_size()
	var tail_src_height := tex_size.y * FISH_TAIL_FRACTION
	var tail_local_height := FISH_SPRITE_SIZE.y * FISH_TAIL_FRACTION
	var body_local_height := FISH_SPRITE_SIZE.y - tail_local_height
	var half_height := FISH_SPRITE_SIZE.y / 2.0
	var half_width := FISH_SPRITE_SIZE.x / 2.0

	var body_src: Rect2
	var tail_src: Rect2
	var body_dest: Rect2
	var tail_dest: Rect2
	var seam_local_y: float

	if FISH_TAIL_AT_TOP:
		tail_src = Rect2(Vector2.ZERO, Vector2(tex_size.x, tail_src_height))
		body_src = Rect2(Vector2(0.0, tail_src_height), Vector2(tex_size.x, tex_size.y - tail_src_height))
		seam_local_y = -half_height + tail_local_height
		body_dest = Rect2(Vector2(-half_width, seam_local_y), Vector2(FISH_SPRITE_SIZE.x, body_local_height))
		tail_dest = Rect2(Vector2(-half_width, -tail_local_height), Vector2(FISH_SPRITE_SIZE.x, tail_local_height))
	else:
		body_src = Rect2(Vector2.ZERO, Vector2(tex_size.x, tex_size.y - tail_src_height))
		tail_src = Rect2(Vector2(0.0, tex_size.y - tail_src_height), Vector2(tex_size.x, tail_src_height))
		seam_local_y = half_height - tail_local_height
		body_dest = Rect2(Vector2(-half_width, -half_height), Vector2(FISH_SPRITE_SIZE.x, body_local_height))
		tail_dest = Rect2(Vector2(-half_width, 0.0), Vector2(FISH_SPRITE_SIZE.x, tail_local_height))

	draw_set_transform(f.pos, base_rotation, Vector2.ONE)
	draw_texture_rect_region(FISH_TEXTURE, body_dest, body_src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var seam_world: Vector2 = f.pos + Vector2(0, seam_local_y).rotated(base_rotation)
	draw_set_transform(seam_world, base_rotation + wobble, Vector2.ONE)
	draw_texture_rect_region(FISH_TEXTURE, tail_dest, tail_src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	# Floor decorations first - rocks rest on the pond bottom, underneath
	# everything that swims.
	for r in _rocks:
		_draw_sprite(r.texture, r.pos, Vector2(r.size, r.size), r.rotation)

	for s in _silt:
		var radius: float = lerpf(0.8, 2.2, s.depth)
		var color := Color(0.85, 0.87, 0.8, lerpf(0.15, 0.4, s.depth))
		draw_circle(s.pos, radius, color)

	for a in _algae:
		_draw_sprite(ALGAE_TEXTURE, a.pos, ALGAE_SPRITE_SIZE, 0.0)
	for d in _daphnia:
		_draw_sprite(DAPHNIA_TEXTURE, d.pos, DAPHNIA_SPRITE_SIZE, d.facing.angle() + DAPHNIA_FACING_OFFSET)
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

	draw_string(ThemeDB.fallback_font, Vector2(8, 20),
		"algae=%d daphnia=%d fish=%d" % [_algae.size(), _daphnia.size(), _fish.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
