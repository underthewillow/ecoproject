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
## Three layers: a filtered-noise water bed (ambient floor), 4 slow
## tonal voices (the ambient pad), and a generative chime that surfaces
## a short melodic phrase every 6-13s on its own independent timer.
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

## Water bed: two cascaded one-pole low-pass stages (12dB/oct) over
## white noise, not one. A single pole let too much high-frequency
## content through and read as "static" rather than a soft water/wind
## bed - cascading a second stage cuts the harsh top end much harder for
## the same cutoff frequency. Range also lowered/darkened and the output
## level pulled down - this layer is meant to sit under everything else,
## not compete with it.
const WATER_CUTOFF_MIN := 0.01
const WATER_CUTOFF_MAX := 0.03
const WATER_AMPLITUDE := 0.12

## Chimes are their own generative voice now, not tied to a population
## milestone (that made them rare - CHIME_MIN/MAX_INTERVAL below is the
## actual pacing knob). Each firing plays a short stepwise phrase through
## the same consonant scale instead of one note.
const CHIME_MIN_INTERVAL := 6.0
const CHIME_MAX_INTERVAL := 13.0
const CHIME_MIN_NOTES := 2
const CHIME_MAX_NOTES := 4
const CHIME_NOTE_GAP := 0.22
const CHIME_OCTAVE := 2.0  # an octave above the ambient voices, so phrases read as foreground events
const CHIME_STEP_WEIGHTS: Array[int] = [-1, -1, 0, 1, 1]  # weighted toward movement over repetition

const EVENT_FADE_RATE := 0.4  # ~2.5s soft ring-out per note, never a hard cutoff
const EVENT_AMP := 0.14

var _time := 0.0

var _water_playback: AudioStreamGeneratorPlayback
var _water_filter_state1 := 0.0
var _water_filter_state2 := 0.0

var _voice_playbacks: Array[AudioStreamGeneratorPlayback] = []
var _voices: Array[Dictionary] = []

var _event_playback: AudioStreamGeneratorPlayback
var _event_phase := 0.0
var _event_freq := 0.0
var _event_env := 0.0

var _chime_timer := 0.0
var _pending_chime_notes: Array[float] = []
var _next_note_timer := 0.0

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

	_chime_timer = randf_range(CHIME_MIN_INTERVAL, CHIME_MAX_INTERVAL)


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
	_update_chimes(delta)


func _fill_water_bed() -> void:
	var to_fill := _water_playback.get_frames_available()
	var health := FakePondState.health(_time)
	# Cutoff drifts slowly with fake ecosystem health so the bed
	# brightens a little when things are thriving and goes duller/murkier
	# when they aren't - cosmetic only, same as the rest of Track B's
	# fake-data hookups.
	var cutoff := lerpf(WATER_CUTOFF_MIN, WATER_CUTOFF_MAX, health)
	for i in to_fill:
		var white := randf_range(-1.0, 1.0)
		_water_filter_state1 += cutoff * (white - _water_filter_state1)
		_water_filter_state2 += cutoff * (_water_filter_state1 - _water_filter_state2)
		var sample := _water_filter_state2 * WATER_AMPLITUDE
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


## Generative chime phrase, on its own independent timer - the Bloom/
## Reflection-style layer: a short melodic gesture that surfaces every
## 6-13s on its own schedule, unrelated to anything else running. Once a
## phrase is queued this drains it note-by-note; otherwise it counts down
## to the next phrase.
func _update_chimes(delta: float) -> void:
	if not _pending_chime_notes.is_empty():
		_next_note_timer -= delta
		if _next_note_timer <= 0.0:
			_trigger_note(_pending_chime_notes.pop_front())
			_next_note_timer = CHIME_NOTE_GAP
		return
	_chime_timer -= delta
	if _chime_timer <= 0.0:
		_chime_timer = randf_range(CHIME_MIN_INTERVAL, CHIME_MAX_INTERVAL)
		_queue_chime_phrase()


## Builds a short stepwise walk through the scale (not random leaps) so
## the phrase reads as a melodic gesture rather than a handful of
## unrelated bell hits - real melodies mostly move by step.
func _queue_chime_phrase() -> void:
	var note_count := randi_range(CHIME_MIN_NOTES, CHIME_MAX_NOTES)
	var degree := randi() % SCALE_RATIOS.size()
	_pending_chime_notes.clear()
	for i in note_count:
		_pending_chime_notes.append(ROOT_FREQ * SCALE_RATIOS[degree] * CHIME_OCTAVE)
		var step: int = CHIME_STEP_WEIGHTS[randi() % CHIME_STEP_WEIGHTS.size()]
		degree = clampi(degree + step, 0, SCALE_RATIOS.size() - 1)
	_next_note_timer = 0.0


## Soft, non-percussive-ish chime note. Phase is deliberately NOT reset
## here - letting it keep accumulating means a pitch change between notes
## glides continuously instead of restarting the waveform, which is what
## keeps rapid note-to-note transitions click-free.
func _trigger_note(freq: float) -> void:
	_event_freq = freq
	_event_env = 1.0


## Manual trigger, kept for Phase 6: once real sim events exist (a
## notable population change, etc.) they can call this directly instead
## of waiting for the generative timer.
func play_event() -> void:
	_trigger_note(_pick_note() * CHIME_OCTAVE)
