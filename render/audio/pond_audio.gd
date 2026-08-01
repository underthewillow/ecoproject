extends Node

## Track B Phase B3 - procedural, generative audio bed (§7.2, §8).
## Nothing here is a pre-rendered clip; every sound is synthesized in
## real time via AudioStreamGenerator.
##
## Aesthetic target: meditation/singing-bowl ambient. Grounded in actual
## research (see commit history for sources): minor pentatonic
## (root/b3/4/5/b7) as the standard "safe" ambient scale; real singing
## bowls have INHARMONIC overtones (non-integer ratios, ~2.76x/5.02x/
## 8.2x) rather than clean harmonics; calming material sits in a low
## register (~20-250Hz); ambient production leans on long reverb and
## low-pass filtering, without which synthesis reads as cheap regardless
## of note choice.
##
## The generative design is Eno-esque: Music for Airports was built from
## ~22 tape loops of differing physical lengths, cycling
## "incommensurably" (never resyncing) - the same independent,
## non-synchronized-timer idea used here for the pad voices and phrase
## generator. The bassline (added after the "give it a groove" request)
## is the one deliberately repeating element - a steady rhythmic anchor
## underneath everything else, which is a common ambient/downtempo
## structure (static pulse + evolving texture on top).
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
const AMBIENT_BUS_NAME := "PondAmbient"

## Minor pentatonic in just intonation: root, minor third, fourth,
## fifth, minor seventh. No semitone-adjacent degrees anywhere (the
## harshest possible clash is structurally impossible), while still
## being a real scale with melodic color rather than a static chord.
const ROOT_FREQ := 55.0  # A1
const PENTATONIC_RATIOS: Array[float] = [1.0, 6.0 / 5.0, 4.0 / 3.0, 3.0 / 2.0, 9.0 / 5.0]
const LOW_PENTATONIC_RATIOS: Array[float] = [1.0, 6.0 / 5.0, 4.0 / 3.0]
const HIGH_PENTATONIC_RATIOS: Array[float] = [4.0 / 3.0, 3.0 / 2.0, 9.0 / 5.0]

## Drone stays fixed on root+fifth always - a real drone doesn't change
## pitch, that's what makes it a drone. Only the detuned pair's slow
## beating gives it any movement at all.
const DRONE_DETUNE_CENTS := 4.0
const DRONE_AMPLITUDE := 0.06

const VOICE_COUNT := 4
const VOICE_MIN_CYCLE := 18.0
const VOICE_MAX_CYCLE := 40.0
const VOICE_OCTAVE := 1.0
const VOICE_PEAK_AMP := 0.10

const PHRASE_MIN_INTERVAL := 7.0
const PHRASE_MAX_INTERVAL := 15.0
const PHRASE_MIN_NOTES := 2
const PHRASE_MAX_NOTES := 4
const PHRASE_NOTE_GAP := 0.55  # meditative pace, not a quick arpeggio
const PHRASE_OCTAVE := 2.0  # one register above the pad voices
const PHRASE_STEP_WEIGHTS: Array[int] = [-1, 0, 0, 1]  # mild bias toward holding/stepping over leaping
const PHRASE_NOTE_AMP := 0.12
const PHRASE_ATTACK_TIME := 0.05  # soft rise - these aren't tied to a visible instant, so a gentle swell-in is fine
const PHRASE_DECAY_RATE := 2.2  # ~1.8s ring-out, bowl-like sustain since these are rare

## Interaction chimes: one voice per concurrent predation event (round
## robin across INTERACTION_VOICE_COUNT voices) rather than a single
## gated voice - a single voice with a cooldown was silently dropping
## any event that arrived while the previous one was still cooling down,
## which is why not every visible eat produced a sound. Tight attack
## time so the chime feels tied to the instant the eat happens rather
## than a beat behind it.
const INTERACTION_VOICE_COUNT := 3
const INTERACTION_OCTAVE := 3.0
const INTERACTION_NOTE_AMP := 0.06
const INTERACTION_ATTACK_TIME := 0.012
const INTERACTION_DECAY_RATE := 5.5  # ~0.7s ring - a soft droplet, not a sustained tone

## A steady, repeating low pulse - the one deliberately non-generative
## element, there to give a felt sense of time/groove while playing
## rather than pure floating ambience. Mostly root, with an occasional
## lift to the fifth; plenty of rests so it reads as a pulse, not a bassline
## melody.
const BASS_OCTAVE := 1.0
const BASS_BEAT_INTERVAL := 0.9  # a slow, steady pulse - well under typical dance tempo
const BASS_PATTERN_DEGREES: Array[int] = [0, -1, -1, -1, 0, -1, 3, -1]  # index into PENTATONIC_RATIOS; -1 = rest
const BASS_NOTE_AMP := 0.11
const BASS_ATTACK_TIME := 0.015
const BASS_DECAY_RATE := 1.6  # a soft, felt pulse, not a percussive hit

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

var _interaction_playbacks: Array[AudioStreamGeneratorPlayback] = []
var _interaction_notes: Array[Dictionary] = []
var _interaction_next_voice := 0

var _bass_playback: AudioStreamGeneratorPlayback
var _bass_note := _new_note_voice()
var _bass_timer := 0.0
var _bass_beat_index := 0

@onready var _drone_player: AudioStreamPlayer = $Drone
@onready var _voice_players: Array[AudioStreamPlayer] = [$Voice1, $Voice2, $Voice3, $Voice4]
@onready var _phrase_player: AudioStreamPlayer = $PhraseChime
@onready var _interaction_players: Array[AudioStreamPlayer] = [$InteractionChime1, $InteractionChime2, $InteractionChime3]
@onready var _bass_player: AudioStreamPlayer = $Bass


func _ready() -> void:
	randomize()
	_ensure_ambient_bus()

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

	for i in INTERACTION_VOICE_COUNT:
		var player := _interaction_players[i]
		player.play()
		_interaction_playbacks.append(player.get_stream_playback())
		_interaction_notes.append(_new_note_voice())

	_bass_player.play()
	_bass_playback = _bass_player.get_stream_playback()

	PondEvents.predation.connect(_on_predation)


## Everything routes through one dedicated bus (not Master directly) so
## the reverb/filter treatment is scoped to this ambient system and
## won't color any unrelated audio a later phase might add. Idempotent -
## safe to call every time the scene loads.
func _ensure_ambient_bus() -> void:
	if AudioServer.get_bus_index(AMBIENT_BUS_NAME) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, AMBIENT_BUS_NAME)
	AudioServer.set_bus_send(idx, "Master")

	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 2600.0
	AudioServer.add_bus_effect(idx, lowpass)

	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.9
	reverb.damping = 0.65
	reverb.spread = 1.0
	reverb.wet = 0.4
	reverb.dry = 1.0
	AudioServer.add_bus_effect(idx, reverb)


static func _new_note_voice() -> Dictionary:
	return {"phase": 0.0, "freq": 0.0, "age": 0.0, "active": false}


func _new_voice_state(initial_elapsed: float = 0.0) -> Dictionary:
	return {
		"phase": 0.0,
		"freq": _pick_tone(PENTATONIC_RATIOS, VOICE_OCTAVE),
		"cycle_length": randf_range(VOICE_MIN_CYCLE, VOICE_MAX_CYCLE),
		"elapsed": initial_elapsed,
	}


func _pick_tone(pool: Array[float], octave: float) -> float:
	var ratio: float = pool[randi() % pool.size()]
	return ROOT_FREQ * ratio * octave


## Two quiet, slightly-inharmonic partials on top of the fundamental -
## a cheap approximation of a bowl's non-integer overtone spectrum
## (research-cited ratios ~2.76x and ~5.02x) instead of clean integer
## harmonics, which read as a synthetic FM-bell patch rather than
## something organic. Output is normalized back to roughly +-1 peak.
static func _bowl_wave(phase_turns: float) -> float:
	var t := phase_turns * TAU
	return (sin(t) + 0.14 * sin(t * 2.756) + 0.07 * sin(t * 5.017)) / 1.21


func _process(delta: float) -> void:
	_time += delta
	_fill_drone()
	_fill_voices()
	_fill_phrase()
	_fill_interaction()
	_fill_bass()
	_update_phrase_timer(delta)
	_update_bass(delta)


## Two drone tones (root and fifth), each a pair of oscillators detuned
## by a few cents so they beat slowly against each other - the closest
## cheap approximation of a bowl's natural, ever-so-slightly-shifting
## hum, instead of a static tone. Always on, quiet - a cushion, not a
## presence. Balance between root and fifth drifts gently with fake
## ecosystem health. Pitch itself never changes - a drone stays put.
func _fill_drone() -> void:
	var to_fill := _drone_playback.get_frames_available()
	var frame_dt := 1.0 / MIX_RATE
	var health := FakePondState.health(_time)
	var root_freq := ROOT_FREQ
	var fifth_freq := ROOT_FREQ * 1.5
	var detune_ratio := pow(2.0, DRONE_DETUNE_CENTS / 1200.0)
	var fifth_mix := lerpf(0.3, 0.55, health)
	for i in to_fill:
		_drone_phase_root_a += root_freq * frame_dt
		_drone_phase_root_b += root_freq * detune_ratio * frame_dt
		_drone_phase_fifth_a += fifth_freq * frame_dt
		_drone_phase_fifth_b += fifth_freq * detune_ratio * frame_dt
		var root_sample := (_bowl_wave(_drone_phase_root_a) + _bowl_wave(_drone_phase_root_b)) * 0.5
		var fifth_sample := (_bowl_wave(_drone_phase_fifth_a) + _bowl_wave(_drone_phase_fifth_b)) * 0.5
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
				# Cycle complete: pick a fresh pentatonic tone and a fresh
				# length so the piece never settles into a repeating
				# loop, only ever-shifting recombinations of the same
				# small palette.
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
			var sample: float = _bowl_wave(v.phase) * envelope
			var safe_sample := clampf(sample, -1.0, 1.0)
			playback.push_frame(Vector2(safe_sample, safe_sample))
		_voices[vi] = v


## Shared per-sample envelope for a single retriggerable note voice - a
## short smoothed attack (never an instant jump, which is what produced
## clicking/"clipping" in an earlier pass) followed by an exponential
## decay. Envelope is a pure function of note.age, which resets to 0 on
## every trigger, so it always starts from true silence - continuous
## even if a new note interrupts one still ringing. attack_time and
## decay_rate are passed in per-voice-type: interaction notes get a much
## tighter attack (feels tied to the instant of the event) and a shorter
## ring than phrase notes (which are rarer and can afford to be more
## spacious).
static func _advance_note(note: Dictionary, frame_dt: float, attack_time: float, decay_rate: float) -> float:
	if not note.active:
		return 0.0
	note.age += frame_dt
	var attack: float = clampf(note.age / attack_time, 0.0, 1.0)
	var decay: float = exp(-maxf(note.age - attack_time, 0.0) * decay_rate)
	var envelope := attack * decay
	note.phase += note.freq * frame_dt
	if envelope < 0.0005 and note.age > attack_time:
		note.active = false
		return 0.0
	return _bowl_wave(note.phase) * envelope


func _fill_phrase() -> void:
	var frame_dt := 1.0 / MIX_RATE
	var to_fill := _phrase_playback.get_frames_available()
	for i in to_fill:
		var sample := _advance_note(_phrase_note, frame_dt, PHRASE_ATTACK_TIME, PHRASE_DECAY_RATE) * PHRASE_NOTE_AMP
		var safe_sample := clampf(sample, -1.0, 1.0)
		_phrase_playback.push_frame(Vector2(safe_sample, safe_sample))


## One buffer per interaction voice, each independently advancing its
## own note - see _on_predation for how voices get assigned.
func _fill_interaction() -> void:
	var frame_dt := 1.0 / MIX_RATE
	for vi in _interaction_notes.size():
		var playback := _interaction_playbacks[vi]
		var to_fill := playback.get_frames_available()
		for i in to_fill:
			var sample := _advance_note(_interaction_notes[vi], frame_dt, INTERACTION_ATTACK_TIME, INTERACTION_DECAY_RATE) * INTERACTION_NOTE_AMP
			var safe_sample := clampf(sample, -1.0, 1.0)
			playback.push_frame(Vector2(safe_sample, safe_sample))


func _fill_bass() -> void:
	var frame_dt := 1.0 / MIX_RATE
	var to_fill := _bass_playback.get_frames_available()
	for i in to_fill:
		var sample := _advance_note(_bass_note, frame_dt, BASS_ATTACK_TIME, BASS_DECAY_RATE) * BASS_NOTE_AMP
		var safe_sample := clampf(sample, -1.0, 1.0)
		_bass_playback.push_frame(Vector2(safe_sample, safe_sample))


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


## Builds a short stepwise walk across the pentatonic scale (not random
## leaps) so the phrase reads as one melodic gesture - real melodic
## motion is mostly stepwise.
func _queue_phrase() -> void:
	var note_count := randi_range(PHRASE_MIN_NOTES, PHRASE_MAX_NOTES)
	var index := randi() % PENTATONIC_RATIOS.size()
	_pending_phrase_notes.clear()
	for i in note_count:
		_pending_phrase_notes.append(ROOT_FREQ * PENTATONIC_RATIOS[index] * PHRASE_OCTAVE)
		var step: int = PHRASE_STEP_WEIGHTS[randi() % PHRASE_STEP_WEIGHTS.size()]
		index = clampi(index + step, 0, PENTATONIC_RATIOS.size() - 1)
	_next_phrase_note_timer = 0.0


## The one deliberately repeating element (§8 exception, noted above) -
## a steady low pulse so the piece has a felt sense of time while
## playing, underneath the otherwise non-repeating generative layers.
func _update_bass(delta: float) -> void:
	_bass_timer += delta
	if _bass_timer < BASS_BEAT_INTERVAL:
		return
	_bass_timer -= BASS_BEAT_INTERVAL
	var degree: int = BASS_PATTERN_DEGREES[_bass_beat_index % BASS_PATTERN_DEGREES.size()]
	_bass_beat_index += 1
	if degree >= 0:
		_trigger_note(_bass_note, ROOT_FREQ * PENTATONIC_RATIOS[degree] * BASS_OCTAVE)


func _trigger_note(note: Dictionary, freq: float) -> void:
	note.freq = freq
	note.age = 0.0
	note.active = true


## Cosmetic predation events (look_study.gd, via the PondEvents autoload)
## feed a second, independent note source, one per event via round-robin
## voice assignment (see INTERACTION_VOICE_COUNT) rather than a single
## gated voice - a shared cooldown was silently dropping events that
## arrived close together, which is why not every visible eat used to
## produce a sound. Mapped to register by trophic level (small predation
## = lower end of the scale, bigger predation = higher) so there's a
## loose, intuitive sense to which notes show up when. Combined with the
## free-running phrase generator above, this is the "melody spontaneously
## forms from interactions" layer - two unrelated note sources, always
## consonant because both draw from the same pentatonic scale,
## occasionally landing near each other in time.
func _on_predation(trophic_level: int) -> void:
	var pool := HIGH_PENTATONIC_RATIOS if trophic_level >= 1 else LOW_PENTATONIC_RATIOS
	var voice_index := _interaction_next_voice
	_interaction_next_voice = (_interaction_next_voice + 1) % _interaction_notes.size()
	_trigger_note(_interaction_notes[voice_index], _pick_tone(pool, INTERACTION_OCTAVE))


## Manual trigger, kept for Phase 6: once real sim events exist they can
## call this directly instead of relying on PondEvents/predation.
func play_event() -> void:
	_trigger_note(_phrase_note, _pick_tone(PENTATONIC_RATIOS, PHRASE_OCTAVE))
