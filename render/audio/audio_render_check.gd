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
##   godot --headless --path . -s res://render/audio/audio_render_check.gd -- --seconds=25 --out=C:/abs/path/out.wav --scene=res://render/look_study/look_study.tscn
##
## Defaults to the full look_study scene (not just pond_audio.tscn alone)
## since that's the only way the creature sim actually runs and fires
## real PondEvents.predation signals - pond_audio.tscn alone never
## exercises the interaction-chime path.

var _elapsed := 0.0
var _duration := 25.0
var _out_path := "user://sanity_check.wav"
var _scene_path := "res://render/look_study/look_study.tscn"
var _record: AudioEffectRecord
var _predation_count := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_duration = float(arg.substr("--seconds=".length()))
		elif arg.begins_with("--out="):
			_out_path = arg.substr("--out=".length())
		elif arg.begins_with("--scene="):
			_scene_path = arg.substr("--scene=".length())

	var bus_idx := AudioServer.get_bus_index("Master")
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, _record)
	_record.set_recording_active(true)

	var scene: PackedScene = load(_scene_path)
	var instance := scene.instantiate()
	root.add_child(instance)

	# Referencing the PondEvents autoload by its global script name doesn't
	# compile inside a custom SceneTree override script the way it does
	# in ordinary scene scripts - look it up as a node instead (autoloads
	# are added as children of the tree root under their configured name).
	var pond_events := root.get_node("PondEvents")
	pond_events.predation.connect(func(_level): _predation_count += 1)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= _duration:
		_record.set_recording_active(false)
		var stream := _record.get_recording()
		stream.save_to_wav(_out_path)
		var stats := _pcm_stats(stream)
		print("saved=%s duration=%.2fs peak=%.4f rms=%.4f has_nan=%s predation_events=%d" % [
			_out_path, _elapsed, stats[0], stats[1], stats[2] > 0.5, _predation_count
		])
		quit()
		return true
	return false


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
