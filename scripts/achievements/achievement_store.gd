class_name AchievementStore
extends RefCounted
## The achievements this computer has unlocked (M18b, GDD §30), kept across every game in their own
## file (user://achievements.cfg), apart from the saves and the settings: [unlocked] id = Unix
## time, [progress] id = the best value measured so far (shown as a bar while it is locked).
## Tests point it somewhere else with `use_file`.

const PATH := "user://achievements.cfg"

static var file_path := PATH
static var _loaded := false
static var _unlocked: Dictionary = {}
static var _progress: Dictionary = {}


## Reads (and later writes) another file; tests and previews use it.
static func use_file(path: String) -> void:
	file_path = path
	_loaded = false


static func is_unlocked(id: StringName) -> bool:
	_load()
	return _unlocked.has(String(id))


## Unix time of the unlock, 0 while locked.
static func unlocked_at(id: StringName) -> int:
	_load()
	return int(_unlocked.get(String(id), 0))


static func count_unlocked() -> int:
	_load()
	return _unlocked.size()


## True when it was locked until now.
static func unlock(id: StringName, time: int = -1) -> bool:
	_load()
	if _unlocked.has(String(id)):
		return false
	_unlocked[String(id)] = time if time >= 0 else int(Time.get_unix_time_from_system())
	_save()
	return true


static func progress(id: StringName) -> int:
	_load()
	return int(_progress.get(String(id), 0))


## Keeps the best value measured; true when it grew (and was written).
static func note_progress(id: StringName, value: int) -> bool:
	_load()
	if value <= progress(id):
		return false
	_progress[String(id)] = value
	_save()
	return true


## Forgets everything in the current file (tests only).
static func clear() -> void:
	_unlocked = {}
	_progress = {}
	_loaded = true
	_save()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_unlocked = {}
	_progress = {}
	var file := ConfigFile.new()
	if file.load(file_path) != OK:
		return
	for section: String in ["unlocked", "progress"]:
		if not file.has_section(section):
			continue
		var target := _unlocked if section == "unlocked" else _progress
		for key in file.get_section_keys(section):
			target[key] = int(file.get_value(section, key, 0))


static func _save() -> void:
	var file := ConfigFile.new()
	for key: String in _unlocked:
		file.set_value("unlocked", key, _unlocked[key])
	for key: String in _progress:
		file.set_value("progress", key, _progress[key])
	file.save(file_path)
