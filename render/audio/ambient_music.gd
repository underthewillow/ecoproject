extends Node

## Stand-in for the procedural audio bed (pond_audio.tscn) while the
## reported clipping/distortion issue there is unresolved (see
## docs/audio-design-notes.md §5 and the audio-clipping-investigation
## memory) - a single looping royalty-free ambient track instead of
## synthesizing anything. pond_audio.tscn/.gd are untouched and still
## wired up correctly; swapping back just means instancing that scene in
## look_study.tscn again instead of this one.
##
## Track: "Tranquility Base" by Kevin MacLeod (incompetech.com), licensed
## under Creative Commons: By Attribution 4.0 License
## (https://creativecommons.org/licenses/by/4.0/). Keep the attribution
## line in README/credits if this ships anywhere - required by the license.

const FADE_IN_TIME := 2.0

@onready var _player: AudioStreamPlayer = $Player

func _ready() -> void:
	var stream: AudioStream = _player.stream
	if stream is AudioStreamMP3:
		stream.loop = true
	_player.volume_db = -80.0
	_player.play()
	var tween := create_tween()
	tween.tween_property(_player, "volume_db", 0.0, FADE_IN_TIME)
