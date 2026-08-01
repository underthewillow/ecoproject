extends Node

## Track B Phase B3 - procedural, generative audio bed (§7.2, §8).
## Nothing here is a pre-rendered clip; every sound is synthesized in
## real time via AudioStreamGenerator. The design is deliberately
## Eno-esque (Music for Airports, Bloom/Reflection): several independent
## voices, each cycling at its own non-synchronized length, drawn from a
## small consonant note palette so whatever happens to overlap at any
## moment is never dissonant - there's no fixed "composition," just a
## system left running. It should sit in the background rather than
## demand attention.
##
## Reads FakePondState the same way look_study.gd does and writes
## nothing back - fully decoupled from the renderer, standing in for
## real Track A sim state until Phase 6.
##
## Pivot note: every voice here is just an AudioStreamPlayer. If
## procedural synthesis doesn't hold up, any of these can be swapped for
## a loaded AudioStreamMP3/OGG (e.g. an ElevenLabs-generated clip)
## without touching the rest of the scene - only the fill functions
## below would change, not the node structure or the public API
## (play_event()).

const FakePondState = preload("res://render/fake_pond_state.gd")

const MIX_RATE := 44100.0

## Just-intonation ratios over a low root - deliberately gapped (no
## adjacent semitones) so no two notes drawn from this set ever produce
## a harsh interval, no matter which voices happen to land together.
const ROOT_FREQ := 110.0  # A2
const SCALE_RATIOS: Array[float] = [1.0, 9.0 / 8.0, 4.0 / 3.0, 3.0 / 2.0, 5.0 / 3.0]
const OCTAVE_WEIGHTS: Array[float] = [0.5, 1.0, 1.0, 2.0]  # bias toward the middle octave

const VOICE_COUNT := 4
const VOICE_MIN_CYCLE := 14.0
const VOICE_MAX_CYCLE := 34.0
const VOICE_PEAK_AMP := 0.16

const EVENT_FADE_RATE := 0.4  # ~2.5s soft fade, never a hard cutoff
const EVENT_AMP := 0.12

var _time := 0.0

var _water_playback: AudioStreamGeneratorPlayback
var _water_filter_state := 0.0

var _voice_playbacks: Array[AudioStreamGeneratorPlayback] = []
var _voices: Array[Dictionary] = []

var _event_playback: AudioStreamGeneratorPlayback
var _event_phase := 0.0
var _event_freq := 0.0
var _event_env := 0.0

var _last_milestone := -1

@onready var _water_player: AudioStreamPlayer = $WaterBed
@onready var _voice_players: Array[AudioStreamPlayer] = [$Voice1, $Voice2, $Voice3, $Voice4]
@onready var _event_player: AudioStreamPlayer = $EventPlayer


func _ready() -> void:
	randomize()

	_water_player.play()
	_water_playback = _water_player.get_stream_playback()

	for i in VOICE_COUNT:
		var player := _voice_players[i]
		player.play()
		_voice_playbacks.append(player.get_stream_playback())
		# Stagger initial phase so voices don't all swell in together on
		# the first cycle - otherwise the independence would only become
		# audible after the first minute or so.
		_voices.append(_new_voice_state(randf() * VOICE_MAX_CYCLE))

	_event_player.play()
	_event_playback = _event_player.get_stream_playback()


func _new_voice_state(initial_elapsed: float = 0.0) -> Dictionary:
	return {
		"phase": 0.0,
		"freq": _pick_note(),
		"cycle_length": randf_range(VOICE_MIN_CYCLE, VOICE_MAX_CYCLE),
		"elapsed": initial_elapsed,
	}


func _pick_note() -> float:
	var octave: float = OCTAVE_WEIGHTS[randi() % OCTAVE_WEIGHTS.size()]
	var ratio: float = SCALE_RATIOS[randi() % SCALE_RATIOS.size()]
	return ROOT_FREQ * ratio * octave


func _process(delta: float) -> void:
	_time += delta
	_fill_water_bed()
	_fill_voices()
	_fill_event()
	_check_milestone()


func _fill_water_bed() -> void:
	var to_fill := _water_playback.get_frames_available()
	var health := FakePondState.health(_time)
	# One-pole low-pass over white noise. Cutoff drifts slowly with fake
	# ecosystem health so the bed brightens a little when things are
	# thriving and goes duller/murkier when they aren't - cosmetic only,
	# same as the rest of Track B's fake-data hookups.
	var cutoff := lerpf(0.015, 0.05, health)
	for i in to_fill:
		var white := randf_range(-1.0, 1.0)
		_water_filter_state += cutoff * (white - _water_filter_state)
		var sample := _water_filter_state * 0.25
		_water_playback.push_frame(Vector2(sample, sample))


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
				# Cycle complete: pick a fresh note and a fresh length so
				# the piece never settles into a repeating loop, only
				# ever-shifting recombinations of the same small palette.
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
			var sample: float = sin(float(v.phase) * TAU) * envelope
			playback.push_frame(Vector2(sample, sample))
		_voices[vi] = v


func _fill_event() -> void:
	var frame_dt := 1.0 / MIX_RATE
	var to_fill := _event_playback.get_frames_available()
	for i in to_fill:
		if _event_env <= 0.0001:
			_event_playback.push_frame(Vector2.ZERO)
			continue
		_event_phase += _event_freq * frame_dt
		_event_env = maxf(_event_env - EVENT_FADE_RATE * frame_dt, 0.0)
		var sample := sin(_event_phase * TAU) * _event_env * EVENT_AMP
		_event_playback.push_frame(Vector2(sample, sample))


## Stand-in for a real population-milestone hook (Phase 6 will have
## actual sim events to attach this to). Fires a soft chime whenever the
## fake daphnia count crosses a multiple of 10, just so the event system
## is actually exercised instead of sitting dead and untested.
func _check_milestone() -> void:
	var milestone := int(FakePondState.daphnia_count(_time) / 10)
	if milestone != _last_milestone and _last_milestone != -1:
		play_event()
	_last_milestone = milestone


## Soft, non-percussive chime, one octave above the ambient voices so it
## reads as an event without ever clashing with them (same note
## palette). Call this for population milestones once real sim events
## exist.
func play_event() -> void:
	_event_freq = _pick_note() * 2.0
	_event_env = 1.0
	_event_phase = 0.0
