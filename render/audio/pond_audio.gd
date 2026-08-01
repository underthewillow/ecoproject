extends Node

## Track B Phase B3 - procedural, generative audio bed (§7.2, §8).
## Nothing here is a pre-rendered clip; every sound is synthesized in
## real time via AudioStreamGenerator.
##
## Aesthetic target (v3, after listening feedback on the first two
## passes): meditation/singing-bowl ambient, not a "song." Everything -
## drone, pad voices, both chime voices - draws pitches from one small
## CHORD_RATIOS set that is only octaves and fifths above a single root.
## There are no thirds or seconds anywhere in the palette, so any two
## notes that happen to land together are guaranteed consonant by
## construction - an open, ambiguous chord rather than a tonal scale,
## closer to how a bowl's own overtones behave than to a melody.
##
## The generative design is still Eno-esque (Music for Airports, Bloom/
## Reflection): independent processes on independent, non-synchronized
## timers, left running against each other with no fixed composition.
## New in v3: a second note source reacts to cosmetic predation events
## (via the PondEvents autoload) so a loose "melody" can emerge from
## ecosystem activity itself, layered against the free-running phrase
## generator - two unrelated processes occasionally landing near each
## other, always consonant because both draw from the same chord.
##
## Reads FakePondState the same way look_study.gd does and writes
## nothing back - fully decoupled from the renderer, standing in for
## real Track A sim state until Phase 6. Listens to PondEvents the same
## way - a one-way subscription, never a reference to the renderer.
##
## Pivot note: every voice here is just an AudioStreamPlayer. If
## procedural synthesis doesn't hold up, any of these can be swapped for
## a loaded AudioStreamMP3/OGG (e.g. an ElevenLabs-generated clip)
## without touching the rest of the scene - only the fill functions
## below would change, not the node structure or the public API
## (play_event()).

const FakePondState = preload("res://render/fake_pond_state.gd")

const MIX_RATE := 44100.0

## The entire harmonic palette. Every ratio here is a power of 2 times
## either 1 or 3/2 relative to the root - i.e. only octaves and fifths,
## deliberately excluding thirds/seconds so there is no scale-step
## interval anywhere that could beat unpleasantly when two voices
## sustain together. Anything drawn from this set, in any combination,
## is consonant.
const ROOT_FREQ := 110.0  # A2
const CHORD_RATIOS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
const LOW_CHORD_RATIOS: Array[float] = [0.5, 1.0, 1.5]
const HIGH_CHORD_RATIOS: Array[float] = [2.0, 3.0, 4.0]

const DRONE_DETUNE_CENTS := 4.0
const DRONE_AMPLITUDE := 0.05

const VOICE_COUNT := 4
const VOICE_MIN_CYCLE := 18.0
const VOICE_MAX_CYCLE := 40.0
const VOICE_PEAK_AMP := 0.10

const PHRASE_MIN_INTERVAL := 7.0
const PHRASE_MAX_INTERVAL := 15.0
const PHRASE_MIN_NOTES := 2
const PHRASE_MAX_NOTES := 4
const PHRASE_NOTE_GAP := 0.55  # meditative pace, not a quick arpeggio
const PHRASE_OCTAVE := 2.0  # one register above the chord's own pad range
const PHRASE_STEP_WEIGHTS: Array[int] = [-1, 0, 0, 1]  # mild bias toward holding/stepping over leaping

const INTERACTION_OCTAVE := 2.0
const INTERACTION_COOLDOWN_MIN := 1.6
const INTERACTION_COOLDOWN_MAX := 3.2

const NOTE_ATTACK_TIME := 0.05  # smooth rise - long enough that no retrigger ever clicks
const NOTE_DECAY_RATE := 2.8  # exponential decay, 1/seconds, after the attack window - ~1.6s to ring out, closer to a bowl's sustain than a quick pluck
const NOTE_AMP := 0.12

var _time := 0.0

var _drone_playback: AudioStreamGeneratorPlayback
var _drone_phase_root_a := 0.0
var _drone_phase_root_b := 0.0
var _drone_phase_fifth_a := 0.0
var _drone_phase_fifth_b := 0.0

var _voice_playbacks: Array[AudioStreamGeneratorPlayback] = []
var _voices: Array[Dictionary] = []

var _phrase_playback: AudioStreamGeneratorPlayback
var _phrase_note := _new_note_voice()
var _phrase_timer := 0.0
var _pending_phrase_notes: Array[float] = []
var _next_phrase_note_timer := 0.0

var _interaction_playback: AudioStreamGeneratorPlayback
var _interaction_note := _new_note_voice()
var _interaction_cooldown := 0.0

@onready var _drone_player: AudioStreamPlayer = $Drone
@onready var _voice_players: Array[AudioStreamPlayer] = [$Voice1, $Voice2, $Voice3, $Voice4]
@onready var _phrase_player: AudioStreamPlayer = $PhraseChime
@onready var _interaction_player: AudioStreamPlayer = $InteractionChime


func _ready() -> void:
	randomize()

	_drone_player.play()
	_drone_playback = _drone_player.get_stream_playback()

	for i in VOICE_COUNT:
		var player := _voice_players[i]
		player.play()
		_voice_playbacks.append(player.get_stream_playback())
		# Stagger initial phase so voices don't all swell in together on
		# the first cycle - otherwise the independence would only become
		# audible after the first minute or so.
		_voices.append(_new_voice_state(randf() * VOICE_MAX_CYCLE))

	_phrase_player.play()
	_phrase_playback = _phrase_player.get_stream_playback()
	_phrase_timer = randf_range(PHRASE_MIN_INTERVAL, PHRASE_MAX_INTERVAL)

	_interaction_player.play()
	_interaction_playback = _interaction_player.get_stream_playback()

	PondEvents.predation.connect(_on_predation)


static func _new_note_voice() -> Dictionary:
	return {"phase": 0.0, "freq": 0.0, "age": 0.0, "active": false}


func _new_voice_state(initial_elapsed: float = 0.0) -> Dictionary:
	return {
		"phase": 0.0,
		"freq": _pick_chord_tone(CHORD_RATIOS, 1.0),
		"cycle_length": randf_range(VOICE_MIN_CYCLE, VOICE_MAX_CYCLE),
		"elapsed": initial_elapsed,
	}


func _pick_chord_tone(pool: Array[float], octave: float) -> float:
	var ratio: float = pool[randi() % pool.size()]
	return ROOT_FREQ * ratio * octave


## Odd-harmonic partials at decreasing amplitude - a cheap approximation
## of a bell/singing-bowl's overtone-rich spectrum instead of a bare
## sine, which read as too thin/synthetic on its own. All partials are
## exact integer multiples of the same fundamental, so they're always in
## tune with themselves no matter which chord tone is playing. Output is
## normalized back to +-1 peak.
static func _bell_wave(phase_turns: float) -> float:
	var t := phase_turns * TAU
	return (sin(t) + 0.18 * sin(t * 3.0) + 0.09 * sin(t * 5.0)) / 1.27


func _process(delta: float) -> void:
	_time += delta
	_fill_drone()
	_fill_voices()
	_fill_phrase()
	_fill_interaction()
	_update_phrase_timer(delta)
	_interaction_cooldown = maxf(_interaction_cooldown - delta, 0.0)


## Two open-fifth drone tones (root and fifth), each a pair of
## oscillators detuned by a few cents so they beat slowly against each
## other - the closest cheap approximation of a bowl's natural,
## ever-so-slightly-shifting hum, instead of a static tone. Always on,
## very quiet - a cushion, not a presence. Balance between root and
## fifth drifts gently with fake ecosystem health.
func _fill_drone() -> void:
	var to_fill := _drone_playback.get_frames_available()
	var frame_dt := 1.0 / MIX_RATE
	var health := FakePondState.health(_time)
	var root_freq := ROOT_FREQ * 0.5
	var fifth_freq := ROOT_FREQ * 1.5
	var detune_ratio := pow(2.0, DRONE_DETUNE_CENTS / 1200.0)
	var fifth_mix := lerpf(0.35, 0.6, health)
	for i in to_fill:
		_drone_phase_root_a += root_freq * frame_dt
		_drone_phase_root_b += root_freq * detune_ratio * frame_dt
		_drone_phase_fifth_a += fifth_freq * frame_dt
		_drone_phase_fifth_b += fifth_freq * detune_ratio * frame_dt
		var root_sample := (_bell_wave(_drone_phase_root_a) + _bell_wave(_drone_phase_root_b)) * 0.5
		var fifth_sample := (_bell_wave(_drone_phase_fifth_a) + _bell_wave(_drone_phase_fifth_b)) * 0.5
		var sample := (root_sample * (1.0 - fifth_mix) + fifth_sample * fifth_mix) * DRONE_AMPLITUDE
		var safe_sample := clampf(sample, -1.0, 1.0)
		_drone_playback.push_frame(Vector2(safe_sample, safe_sample))


func _fill_voices() -> void:
	var frame_dt := 1.0 / MIX_RATE
	for vi in _voices.size():
		var v: Dictionary = _voices[vi]
		var playback := _voice_playbacks[vi]
		var to_fill := playback.get_frames_available()
		for i in to_fill:
			v.elapsed += frame_dt
			var t: float = v.elapsed / v.cycle_length
			if t >= 1.0:
				# Cycle complete: pick a fresh chord tone and a fresh
				# length so the piece never settles into a repeating
				# loop, only ever-shifting recombinations of the same
				# small, always-consonant palette.
				var fresh := _new_voice_state()
				v.freq = fresh.freq
				v.cycle_length = fresh.cycle_length
				v.elapsed = 0.0
				t = 0.0
			# Raised-cosine swell in and out across the whole cycle - no
			# attack/decay transients, nothing that reads as a "note
			# hit." pow() sharpens the shoulders so voices spend more
			# time near silence than at full volume, keeping the texture
			# open rather than dense.
			var envelope: float = pow(0.5 - 0.5 * cos(t * TAU), 1.5) * VOICE_PEAK_AMP
			v.phase += float(v.freq) * frame_dt
			var sample: float = _bell_wave(v.phase) * envelope
			var safe_sample := clampf(sample, -1.0, 1.0)
			playback.push_frame(Vector2(safe_sample, safe_sample))
		_voices[vi] = v


## Shared per-sample envelope for a single retriggerable note voice - a
## short smoothed attack (never an instant jump, which is what produced
## the clicking/"clipping" in the previous pass) followed by an
## exponential decay. Envelope is a pure function of note.age, which
## resets to 0 on every trigger, so it always starts from true silence -
## continuous even if a new note interrupts one still ringing.
static func _advance_note(note: Dictionary, frame_dt: float) -> float:
	if not note.active:
		return 0.0
	note.age += frame_dt
	var attack: float = clampf(note.age / NOTE_ATTACK_TIME, 0.0, 1.0)
	var decay: float = exp(-maxf(note.age - NOTE_ATTACK_TIME, 0.0) * NOTE_DECAY_RATE)
	var envelope := attack * decay
	note.phase += note.freq * frame_dt
	if envelope < 0.0005 and note.age > NOTE_ATTACK_TIME:
		note.active = false
		return 0.0
	return _bell_wave(note.phase) * envelope


func _fill_phrase() -> void:
	var frame_dt := 1.0 / MIX_RATE
	var to_fill := _phrase_playback.get_frames_available()
	for i in to_fill:
		var sample := _advance_note(_phrase_note, frame_dt) * NOTE_AMP
		var safe_sample := clampf(sample, -1.0, 1.0)
		_phrase_playback.push_frame(Vector2(safe_sample, safe_sample))


func _fill_interaction() -> void:
	var frame_dt := 1.0 / MIX_RATE
	var to_fill := _interaction_playback.get_frames_available()
	for i in to_fill:
		var sample := _advance_note(_interaction_note, frame_dt) * NOTE_AMP
		var safe_sample := clampf(sample, -1.0, 1.0)
		_interaction_playback.push_frame(Vector2(safe_sample, safe_sample))


## Free-running generative phrase (§8) - the Bloom/Reflection-style
## layer: a short melodic gesture surfacing every 7-15s on its own
## schedule, unrelated to anything else running. Once a phrase is queued
## this drains it note-by-note; otherwise it counts down to the next one.
func _update_phrase_timer(delta: float) -> void:
	if not _pending_phrase_notes.is_empty():
		_next_phrase_note_timer -= delta
		if _next_phrase_note_timer <= 0.0:
			_trigger_note(_phrase_note, _pending_phrase_notes.pop_front())
			_next_phrase_note_timer = PHRASE_NOTE_GAP
		return
	_phrase_timer -= delta
	if _phrase_timer <= 0.0:
		_phrase_timer = randf_range(PHRASE_MIN_INTERVAL, PHRASE_MAX_INTERVAL)
		_queue_phrase()


## Builds a short stepwise walk across chord-tone positions (not random
## leaps) so the phrase reads as one melodic gesture - real melodic
## motion is mostly stepwise, even when, as here, every "step" is
## actually an octave or a fifth rather than a scale degree.
func _queue_phrase() -> void:
	var note_count := randi_range(PHRASE_MIN_NOTES, PHRASE_MAX_NOTES)
	var index := randi() % CHORD_RATIOS.size()
	_pending_phrase_notes.clear()
	for i in note_count:
		_pending_phrase_notes.append(ROOT_FREQ * CHORD_RATIOS[index] * PHRASE_OCTAVE)
		var step: int = PHRASE_STEP_WEIGHTS[randi() % PHRASE_STEP_WEIGHTS.size()]
		index = clampi(index + step, 0, CHORD_RATIOS.size() - 1)
	_next_phrase_note_timer = 0.0


func _trigger_note(note: Dictionary, freq: float) -> void:
	note.freq = freq
	note.age = 0.0
	note.active = true


## Cosmetic predation events (look_study.gd, via the PondEvents autoload)
## feed a second, independent note source - throttled by a cooldown so a
## burst of eating doesn't turn into a flurry of notes, and mapped to
## register by trophic level (small predation = lower chord tone, bigger
## predation = higher) so there's a loose, intuitive sense to which notes
## show up when. Combined with the free-running phrase generator above,
## this is the "melody spontaneously forms from interactions" layer -
## two unrelated note sources, always consonant because both draw from
## the same chord, occasionally landing near each other in time.
func _on_predation(trophic_level: int) -> void:
	if _interaction_cooldown > 0.0:
		return
	_interaction_cooldown = randf_range(INTERACTION_COOLDOWN_MIN, INTERACTION_COOLDOWN_MAX)
	var pool := HIGH_CHORD_RATIOS if trophic_level >= 1 else LOW_CHORD_RATIOS
	_trigger_note(_interaction_note, _pick_chord_tone(pool, INTERACTION_OCTAVE))


## Manual trigger, kept for Phase 6: once real sim events exist they can
## call this directly instead of relying on PondEvents/predation.
func play_event() -> void:
	_trigger_note(_phrase_note, _pick_chord_tone(CHORD_RATIOS, PHRASE_OCTAVE))
