class_name SaveSystem
extends RefCounted
## Save slots on disk (GDD §10.1): one autosave plus MANUAL_SLOTS manual slots, each a JSON file
## {"save_version", "saved_at", "summary", "game"} in `folder`. Older versions are upgraded step
## by step on load; newer ones are refused. Files are written to a temp file first and then
## renamed, so a crash never leaves a half-written save.

const SAVE_VERSION := 5
## Saves older than this cannot be loaded: v4 (M14b) replaced the world of 6 clans with the
## 24-clan campaign map, and v5 (M18e) the 5×5 map with the 6×6 one of 35 clans; an old game
## cannot be moved onto the new map.
const OLDEST_LOADABLE := 5
const AUTO_SLOT := "auto"
const MANUAL_SLOTS := 3
const DEFAULT_FOLDER := "user://saves"

## Where the files live (tests use their own folder).
var folder: String


func _init(p_folder: String = DEFAULT_FOLDER) -> void:
	folder = p_folder


## Every slot in display order: the autosave first.
static func all_slots() -> Array[String]:
	var slots: Array[String] = [AUTO_SLOT]
	for i in MANUAL_SLOTS:
		slots.append("slot_%d" % (i + 1))
	return slots


static func slot_name(slot: String) -> String:
	return "Tự động" if slot == AUTO_SLOT else "Ô lưu %s" % slot.trim_prefix("slot_")


func path(slot: String) -> String:
	return "%s/%s.json" % [folder, slot]


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Writes the game to the slot. Returns OK or the file error.
func save(state: KingdomState, slot: String) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		return error
	var data := {"save_version": SAVE_VERSION, "saved_at": Time.get_unix_time_from_system(),
			"summary": state.save_summary(), "game": state.to_save()}
	var temp_path := path(slot) + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(temp_path, path(slot))


## Reads a slot: {"game": Dictionary} on success, {"error": String} (in Vietnamese) otherwise.
## The game data is already upgraded to SAVE_VERSION.
func load_slot(slot: String) -> Dictionary:
	var data := _read(slot)
	if data.is_empty():
		return {"error": "Không đọc được bản lưu (file hỏng hoặc không còn)."}
	var version := int(data.get("save_version", 0))
	if version > SAVE_VERSION:
		return {"error": "Bản lưu từ phiên bản game mới hơn, chưa tải được."}
	if version < 1 or not data.has("game"):
		return {"error": "Bản lưu không hợp lệ."}
	if version < OLDEST_LOADABLE:
		return {"error": "Bản lưu từ phiên bản cũ (bản đồ gia tộc nhỏ hơn), không tải được với bản đồ 6×6 mới. Hãy bắt đầu ván mới."}
	return {"game": migrate(data.game, version)}


## {"turn", "cells", "soldiers", "saved_at"} (ints) for the slot list, or {} when the slot is empty or unreadable.
func slot_info(slot: String) -> Dictionary:
	var data := _read(slot)
	if data.is_empty() or not data.has("summary"):
		return {}
	var info := {}
	for key in ["turn", "cells", "soldiers"]:
		info[key] = int(data.summary.get(key, 0))
	info["difficulty"] = int(data.summary.get("difficulty", Difficulty.Level.NORMAL))
	info["saved_at"] = int(data.get("saved_at", 0))
	return info


## The slot saved most recently, or "" when there is none.
func latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot in all_slots():
		var info := slot_info(slot)
		if not info.is_empty() and info.saved_at > best_time:
			best = slot
			best_time = info.saved_at
	return best


func delete(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(path(slot))


## Upgrades game data written by `version` to SAVE_VERSION, one step at a time. When the save
## format changes: bump SAVE_VERSION and add a `_migrate_from_N` step below.
static func migrate(game: Dictionary, version: int) -> Dictionary:
	var data := game.duplicate(true)
	while version < SAVE_VERSION:
		match version:
			1:
				_migrate_from_1(data)
			2:
				_migrate_from_2(data)
		version += 1
	return data


## v3 (economy v2): the stable became the farm; every building cell has a level (1).
static func _migrate_from_2(data: Dictionary) -> void:
	for cell: Dictionary in data.get("board", {}).get("cells", []):
		if cell.get("building", "") == "stable":
			cell["building"] = "farm"
		cell["level"] = 1


## v2 (M11e): squads have XP; generals have a level, XP and unspent points.
static func _migrate_from_1(data: Dictionary) -> void:
	for squad: Dictionary in data.get("army", []):
		squad["xp"] = 0.0
	var generals: Dictionary = data.get("generals", {})
	for key in ["generals", "candidates"]:
		for general: Dictionary in generals.get(key, []):
			general.merge({"level": 1, "xp": 0, "points": 0})


func _read(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	# JSON.new().parse stays quiet on a broken file (JSON.parse_string would log an error).
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path(slot))) != OK:
		return {}
	return json.data if json.data is Dictionary else {}
