class_name GameSettings
extends RefCounted
## Player preferences kept on this computer (user://settings.cfg), apart from the saves: map effects
## (building animations and walkers, M13c), music and sound volumes and full screen (M14a), the
## notice column's folded items and whether the column is open (M14b), the UI scale (M15a).
## Changed in SettingsWindow; `changed` lets open scenes apply them at once.

const PATH := "user://settings.cfg"
const DEFAULT_MUSIC_VOLUME := 0.6
const DEFAULT_SOUND_VOLUME := 0.8
## Cỡ giao diện (M15a): 0 = tự chọn theo màn hình (Touch.auto_ui_scale), else MIN..MAX.
const AUTO_UI_SCALE := 0.0
const MIN_UI_SCALE := 0.8
const MAX_UI_SCALE := 2.0

## Tests point this somewhere else (`use_file`) so they never touch the player's settings.
static var file_path := PATH
static var _loaded := false
static var _map_effects := true
static var _music_volume := DEFAULT_MUSIC_VOLUME
static var _sound_volume := DEFAULT_SOUND_VOLUME
static var _fullscreen := false
static var _ui_scale := AUTO_UI_SCALE
static var _folded_notices: Array[String] = []
static var _notices_open := true
static var _legendary_unlocked := false
## Emitted after any setting changed (a static signal: listeners connect to `GameSettings.notifier.changed`).
static var notifier := Notifier.new()


class Notifier:
	extends RefCounted
	signal changed


static func map_effects() -> bool:
	_load()
	return _map_effects


static func music_volume() -> float:
	_load()
	return _music_volume


static func sound_volume() -> float:
	_load()
	return _sound_volume


static func fullscreen() -> bool:
	_load()
	return _fullscreen


## The player's UI scale, or AUTO_UI_SCALE (0) to follow the screen.
static func ui_scale() -> float:
	_load()
	return _ui_scale


## Notices.key()s of the items the player folded away.
static func folded_notices() -> Array[String]:
	_load()
	return _folded_notices.duplicate()


static func notices_open() -> bool:
	_load()
	return _notices_open


static func set_notice_folded(notice_key: String, folded: bool) -> void:
	_load()
	if folded == _folded_notices.has(notice_key):
		return
	if folded:
		_folded_notices.append(notice_key)
	else:
		_folded_notices.erase(notice_key)
	_store("notices", "folded", _folded_notices)


static func set_notices_open(open: bool) -> void:
	_load()
	_notices_open = open
	_store("notices", "open", open)


## Legendary difficulty opens after a game won on Normal or Hard (GDD §15 M14h).
static func legendary_unlocked() -> bool:
	_load()
	return _legendary_unlocked


static func unlock_legendary() -> void:
	_load()
	if _legendary_unlocked:
		return
	_legendary_unlocked = true
	_store("progress", "legendary_unlocked", true)


static func set_map_effects(on: bool) -> void:
	_load()
	_map_effects = on
	_store("display", "map_effects", on)


## 0..1.
static func set_music_volume(volume: float) -> void:
	_load()
	_music_volume = clampf(volume, 0.0, 1.0)
	_store("audio", "music_volume", _music_volume)


## 0..1.
static func set_sound_volume(volume: float) -> void:
	_load()
	_sound_volume = clampf(volume, 0.0, 1.0)
	_store("audio", "sound_volume", _sound_volume)


static func set_fullscreen(on: bool) -> void:
	_load()
	_fullscreen = on
	_store("display", "fullscreen", on)


## AUTO_UI_SCALE, or a scale clamped to MIN_UI_SCALE..MAX_UI_SCALE.
static func set_ui_scale(scale: float) -> void:
	_load()
	_ui_scale = AUTO_UI_SCALE if scale <= AUTO_UI_SCALE else clampf(scale, MIN_UI_SCALE, MAX_UI_SCALE)
	_store("display", "ui_scale", _ui_scale)


## Reads and writes `path` from now on, forgetting what was read (tests use their own file).
static func use_file(path: String) -> void:
	file_path = path
	_loaded = false


static func _store(section: String, key: String, value: Variant) -> void:
	var file := ConfigFile.new()
	file.load(file_path)
	file.set_value(section, key, value)
	file.save(file_path)
	notifier.changed.emit()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	file.load(file_path)
	_map_effects = bool(file.get_value("display", "map_effects", true))
	_fullscreen = bool(file.get_value("display", "fullscreen", false))
	var scale := float(file.get_value("display", "ui_scale", AUTO_UI_SCALE))
	_ui_scale = AUTO_UI_SCALE if scale <= AUTO_UI_SCALE else clampf(scale, MIN_UI_SCALE, MAX_UI_SCALE)
	_music_volume = clampf(float(file.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	_sound_volume = clampf(float(file.get_value("audio", "sound_volume", DEFAULT_SOUND_VOLUME)), 0.0, 1.0)
	_folded_notices.assign(file.get_value("notices", "folded", []))
	_notices_open = bool(file.get_value("notices", "open", true))
	_legendary_unlocked = bool(file.get_value("progress", "legendary_unlocked", false))
