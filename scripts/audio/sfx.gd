class_name Sfx
extends RefCounted
## Sounds and music by id (GDD §13, M14a). Static calls usable anywhere; they go to the
## SoundPlayer autoload and do nothing without it (headless tests). Generated files live in
## assets/audio/sfx/ and assets/audio/music/ (tools/audio/sound_gen.py); a file of the same name in
## assets/audio/custom/ (.ogg, .wav or .mp3) replaces the generated one.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const CUSTOM_DIR := "res://assets/audio/custom/"
const CUSTOM_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

## Every effect the game plays (each has a generated file).
const EFFECTS: Array[StringName] = [&"click", &"open", &"error", &"place_land", &"build", &"complete", &"upgrade",
		&"recruit", &"demolish", &"end_turn", &"coins", &"event", &"forge", &"level_up", &"bird_1", &"bird_2",
		&"hammer", &"battle_start", &"bow", &"crossbow", &"gun", &"cannon", &"charge", &"clash_1", &"clash_2",
		&"clash_3", &"horn", &"general_fallen", &"stratagem"]
## Looping music, and the short pieces played once (`sting`).
const MUSIC: Array[StringName] = [&"menu", &"kingdom", &"battle", &"expedition"]
const STINGS: Array[StringName] = [&"victory", &"defeat"]


## Plays effect `id` (`volume_db` relative, pitch varied a little so repeats sound alive).
static func play(id: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	var player := _player()
	if player != null:
		player.play_effect(id, volume_db, pitch_jitter)


## Fades over to looping music `id` (nothing if it is already playing).
static func music(id: StringName) -> void:
	var player := _player()
	if player != null:
		player.play_music(id)


## Stops the music and plays the short piece `id` once.
static func sting(id: StringName) -> void:
	var player := _player()
	if player != null:
		player.play_sting(id)


## The stream for `id` in `folder` (SFX_DIR or MUSIC_DIR), the player's own file first; null when missing.
static func load_stream(folder: String, id: StringName) -> AudioStream:
	for extension in CUSTOM_EXTENSIONS:
		var custom := "%s%s.%s" % [CUSTOM_DIR, id, extension]
		if ResourceLoader.exists(custom):
			return load(custom)
	var generated := "%s%s.wav" % [folder, id]
	return load(generated) if ResourceLoader.exists(generated) else null


static func _player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"SoundPlayer") if tree != null and tree.root != null else null
