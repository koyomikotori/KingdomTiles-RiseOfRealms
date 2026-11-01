extends Node
## Autoload "SoundPlayer" (GDD §13, M14a): plays effects on a few voices of the "SFX" bus and the
## music on the "Music" bus (fading between pieces, looping), with the volumes and the full screen
## choice from GameSettings. Every button clicks by itself (`node_added`). Use it through Sfx.

const VOICES := 10
## The same effect is not started again within this many seconds (a volley of ten archers is one sound).
const MIN_GAP := 0.06
## Seconds to fade from one piece of music to the next.
const FADE := 0.8
const SILENT_DB := -60.0
## Effects pressed buttons play (buttons with the meta "silent" stay quiet).
const BUTTON_SOUND := &"click"

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played: Dictionary[StringName, float] = {}
var _cache: Dictionary[String, AudioStream] = {}
var _music: Array[AudioStreamPlayer] = []
var _active := 0
## The fade running on each music player: a new piece kills the old fade first, or a fade-out
## started a moment earlier would still stop the player that now plays the new piece (switching
## music twice within FADE seconds left the expedition silent).
var _fades: Array[Tween] = [null, null]
var _current_music: StringName = &""
var _sting: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")
	for i in VOICES:
		_voices.append(_new_player(&"SFX"))
	for i in 2:
		var player := _new_player(&"Music")
		player.finished.connect(_on_music_finished.bind(player))
		_music.append(player)
	_sting = _new_player(&"Music")
	GameSettings.notifier.changed.connect(apply_settings)
	apply_settings()
	get_tree().node_added.connect(_on_node_added)


func apply_settings() -> void:
	_set_bus_volume(&"Music", GameSettings.music_volume())
	_set_bus_volume(&"SFX", GameSettings.sound_volume())
	var mode := DisplayServer.window_get_mode()
	var fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if GameSettings.fullscreen() and not fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not GameSettings.fullscreen() and fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func play_effect(id: StringName, volume_db: float, pitch_jitter: float) -> void:
	if not is_node_ready():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(id, -1.0) < MIN_GAP:
		return
	var stream := _stream(Sfx.SFX_DIR, id)
	if stream == null:
		return
	_last_played[id] = now
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


func play_music(id: StringName) -> void:
	if not is_node_ready() or id == _current_music:
		return
	var stream := _stream(Sfx.MUSIC_DIR, id)
	if stream == null:
		return
	_current_music = id
	_sting.stop()
	_fade_out(_music[_active])
	_active = 1 - _active
	var player := _music[_active]
	_kill_fade(_active)
	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	_fades[_active] = create_tween()
	_fades[_active].tween_property(player, "volume_db", 0.0, FADE)


func play_sting(id: StringName) -> void:
	if not is_node_ready():
		return
	var stream := _stream(Sfx.MUSIC_DIR, id)
	if stream == null:
		return
	_current_music = &""
	_fade_out(_music[_active])
	_sting.stream = stream
	_sting.play()


func _fade_out(player: AudioStreamPlayer) -> void:
	if not player.playing:
		return
	var index := _music.find(player)
	_kill_fade(index)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, FADE)
	tween.tween_callback(player.stop)
	_fades[index] = tween


func _kill_fade(index: int) -> void:
	if _fades[index] != null and _fades[index].is_valid():
		_fades[index].kill()
	_fades[index] = null


## Music loops: the piece starts again when it ends, unless something else took over.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player == _music[_active] and _current_music != &"":
		player.play()


func _stream(folder: String, id: StringName) -> AudioStream:
	var key := folder + id
	if not _cache.has(key):
		_cache[key] = Sfx.load_stream(folder, id)
	return _cache[key]


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"silent"):
		node.pressed.connect(func() -> void: play_effect(BUTTON_SOUND, -4.0, 0.03))


func _new_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func _set_bus_volume(bus_name: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))
