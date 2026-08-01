extends SceneTree

## Technical-only sanity check for Phase B3's procedural audio (§8) - NOT
## a substitute for actually listening to it. Runs the real pond_audio
## scene for a real wall-clock duration (the generator's playback
## position advances with actual audio-thread time, not simulated frame
## steps, so this can't be sped up) with an AudioEffectRecord tapped onto
## the Master bus, then saves the result as a WAV. Lets the raw signal be
## checked for silence/NaN/clipping without a human ear, and gives a file
## that can be double-clicked and played without launching the project.
##
## Run headless:
##   godot --headless --path . -s res://render/audio/audio_render_check.gd -- --seconds=25 --out=C:/abs/path/out.wav --scene=res://render/look_study/look_study.tscn --trigger-at=3.0
##
## Defaults to the full look_study scene (not just pond_audio.tscn alone)
## since that's the only way the creature sim actually runs and fires
## real PondEvents.predation signals - pond_audio.tscn alone never
## exercises the interaction-chime path.
##
## --trigger-at=T fires one manual predation event at wall-clock time T
## and measures how many milliseconds pass in the recorded WAV before
## that event's audio is actually audible above a small threshold - the
## only way to directly measure the fixed pipeline latency (mainly
## AudioStreamGenerator buffer_length) rather than reasoning about it
## abstractly. For a clean measurement, pair with
## --scene=res://render/audio/pond_audio.tscn, which has no ongoing
## predation activity of its own to obscure the single manual trigger.

const ALL_LAYER_NAMES: Array[String] = [
	"Drone", "Voice1", "Voice2", "Voice3", "Voice4", "PhraseChime",
	"InteractionChime1", "InteractionChime2", "InteractionChime3", "Bass",
]

var _elapsed := 0.0
var _duration := 25.0
var _out_path := "user://sanity_check.wav"
var _scene_path := "res://render/look_study/look_study.tscn"
var _record: AudioEffectRecord
var _predation_count := 0
var _pond_events: Node
var _trigger_at := -1.0
var _trigger_fired := false
var _trigger_actual_time := -1.0
var _isolate: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_duration = float(arg.substr("--seconds=".length()))
		elif arg.begins_with("--out="):
			_out_path = arg.substr("--out=".length())
		elif arg.begins_with("--scene="):
			_scene_path = arg.substr("--scene=".length())
		elif arg.begins_with("--trigger-at="):
			_trigger_at = float(arg.substr("--trigger-at=".length()))
		elif arg.begins_with("--isolate="):
			_isolate = arg.substr("--isolate=".length())

	var bus_idx := AudioServer.get_bus_index("Master")
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, _record)
	_record.set_recording_active(true)

	var scene: PackedScene = load(_scene_path)
	var instance := scene.instantiate()
	root.add_child(instance)

	# For a latency measurement, mute every layer except the interaction
	# chime voices - pond_audio.tscn is never actually silent (drone +
	# pad voices run continuously), which makes a clean amplitude-based
	# onset detection impossible against that background. This exercises
	# the real interaction-chime code path (same buffer_length, same
	# _fill_interaction/_on_predation) with everything else silenced
	# externally, rather than baking test-only behavior into pond_audio.gd.
	if _trigger_at >= 0.0:
		_mute_all_except(instance, ["InteractionChime1", "InteractionChime2", "InteractionChime3"])
	elif not _isolate.is_empty():
		_mute_all_except(instance, _isolate.split(","))

	# Referencing the PondEvents autoload by its global script name doesn't
	# compile inside a custom SceneTree override script the way it does
	# in ordinary scene scripts - look it up as a node instead (autoloads
	# are added as children of the tree root under their configured name).
	_pond_events = root.get_node("PondEvents")
	_pond_events.predation.connect(func(_level): _predation_count += 1)


## Silences every named layer except those in keep_names - used to
## measure one layer's contribution in isolation (--isolate=Bass) or to
## clear the background for a latency measurement (--trigger-at). volume_db,
## not .stop() - stopping would tear down the playback object pond_audio.gd
## is still holding a reference to and pushing frames into every frame,
## risking a runtime error. Silencing via volume leaves everything running
## normally, just inaudible.
func _mute_all_except(scene_instance: Node, keep_names: Array) -> void:
	var pond_audio := scene_instance if scene_instance.name == "PondAudio" else scene_instance.find_child("PondAudio", true, false)
	if pond_audio == null:
		return
	for player_name in ALL_LAYER_NAMES:
		if player_name in keep_names:
			continue
		var player: AudioStreamPlayer = pond_audio.get_node_or_null(player_name)
		if player:
			player.volume_db = -80.0


func _process(delta: float) -> bool:
	_elapsed += delta

	if _trigger_at >= 0.0 and not _trigger_fired and _elapsed >= _trigger_at:
		_trigger_fired = true
		_trigger_actual_time = _elapsed
		_pond_events.predation.emit(1)

	if _elapsed >= _duration:
		_record.set_recording_active(false)
		var stream := _record.get_recording()
		stream.save_to_wav(_out_path)
		var stats := _pcm_stats(stream)
		print("saved=%s duration=%.2fs peak=%.4f rms=%.4f has_nan=%s predation_events=%d" % [
			_out_path, _elapsed, stats[0], stats[1], stats[2] > 0.5, _predation_count
		])
		if _trigger_fired:
			var latency_ms := _measure_latency_ms(stream, _trigger_actual_time)
			print("trigger_requested_at=%.4fs trigger_actually_fired_at=%.4fs measured_latency_ms=%.1f" % [
				_trigger_at, _trigger_actual_time, latency_ms
			])
		quit()
		return true
	return false


## Scans forward from trigger_time for the first point that clearly
## exceeds the PRE-trigger baseline level (not a fixed absolute
## threshold) - pond_audio.tscn is never truly silent (drone + pad
## voices run continuously), so an absolute threshold would just catch
## whatever the ambient level already was rather than the chime's actual
## onset. The baseline is measured from the 100ms immediately before the
## trigger, which is short enough that the slow-moving ambient layers
## won't have shifted meaningfully by the time the trigger fires.
## Returns milliseconds, or -1 if no clear rise was found in the search
## window.
func _measure_latency_ms(stream: AudioStreamWAV, trigger_time: float) -> float:
	var bytes := stream.data
	var mix_rate := 44100
	var start_sample := int(trigger_time * mix_rate)

	var baseline_samples := mix_rate / 10
	var baseline_peak := _peak_in_range(bytes, maxi(0, start_sample - baseline_samples), start_sample)
	var onset_threshold := baseline_peak * 2.0 + 0.015

	var search_window_samples := mix_rate * 1
	var window := 8
	var i := start_sample
	var end_sample := start_sample + search_window_samples
	while i < end_sample:
		var local_peak := _peak_in_range(bytes, i, i + window)
		if local_peak > onset_threshold:
			return float(i - start_sample) / float(mix_rate) * 1000.0
		i += window
	return -1.0


func _peak_in_range(bytes: PackedByteArray, from_sample: int, to_sample: int) -> float:
	var peak := 0.0
	var i := from_sample * 4  # 16-bit stereo = 4 bytes/frame
	var end := mini(bytes.size() - 1, to_sample * 4)
	while i + 1 < end:
		var raw := bytes[i] | (bytes[i + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		peak = maxf(peak, absf(raw / 32768.0))
		i += 4
	return peak


func _pcm_stats(stream: AudioStreamWAV) -> PackedFloat32Array:
	var bytes := stream.data
	var peak := 0.0
	var sum_sq := 0.0
	var count := 0
	var has_nan := 0.0
	var i := 0
	while i + 1 < bytes.size():
		var raw := bytes[i] | (bytes[i + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		var normalized := raw / 32768.0
		if is_nan(normalized):
			has_nan = 1.0
		peak = maxf(peak, absf(normalized))
		sum_sq += normalized * normalized
		count += 1
		i += 2
	var rms := sqrt(sum_sq / maxf(float(count), 1.0))
	return PackedFloat32Array([peak, rms, has_nan])
