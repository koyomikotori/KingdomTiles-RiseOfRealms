class_name Achievements
extends RefCounted
## Steam-like achievements (M18b, GDD §30): the list lives in data/achievements/achievements.json
## ({id, category, title, description, measure, target, hidden?, reward?}); each one is reached
## when `measure(entry.measure, state)` ≥ `target` in a game being played. What is unlocked is kept
## by AchievementStore, across every game. Rewards are looks only, chosen on the new game screen:
## {"color": "rrggbb", "name"} an army color, {"honor": "…"} a title under the ruler's name,
## {"frame": id, "name"} a portrait frame for the ruler (assets/portraits/frame_ruler_<id>.png).

const PATH := "res://data/achievements/achievements.json"
## Display order and names; every category has a medal assets/icons/achievement_<category>.png.
const CATEGORIES: Dictionary[StringName, String] = {&"economy": "Kinh tế", &"military": "Quân sự",
		&"diplomacy": "Ngoại giao", &"officers": "Tướng sĩ", &"adventure": "Phiêu lưu",
		&"conquest": "Chinh phục"}
## The medal of a hidden achievement still locked.
const SECRET_ICON := &"achievement_secret"
## The fastest win (measure won_fast).
const FAST_WIN_TURN := 150
## Measures read from KingdomState.stats.
const STAT_MEASURES: Array[StringName] = [&"battles_won", &"items_forged", &"expeditions_cleared",
		&"spars_won", &"memories_won", &"market_buys", &"events_answered", &"tutorial_finished",
		&"commanders_lost", &"agents_caught", &"deserted", &"duels_won"]

static var _all: Array[Dictionary] = []


## Every achievement, in the file's order; ids, categories and measures as StringNames.
static func all() -> Array[Dictionary]:
	if _all.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Array:
			for raw: Dictionary in parsed:
				var entry := raw.duplicate()
				entry.id = StringName(raw.id)
				entry.category = StringName(raw.category)
				entry.measure = StringName(raw.measure)
				entry.target = int(raw.target)
				entry.hidden = bool(raw.get("hidden", false))
				entry.reward = raw.get("reward", {})
				_all.append(entry)
	return _all


static func find(id: StringName) -> Dictionary:
	for entry in all():
		if entry.id == id:
			return entry
	return {}


## The value `measure` has in this game (see the JSON's measures).
static func measure(what: StringName, state: KingdomState) -> int:
	if what in STAT_MEASURES:
		return int(state.stats.get(String(what), 0))
	match what:
		&"buildings":
			var count := 0
			for id in state.buildings:
				count += state.board.count_buildings(id)
			return count
		&"top_building_level":
			var best := 0
			for id in state.buildings:
				if not state.buildings[id].level_yields.is_empty():
					best = maxi(best, state.board.highest_building_level(id))
			return best
		&"cells":
			return state.board.count_owned_cells()
		&"castle_level":
			return state.castle_level
		&"food":
			return state.stockpile.get_amount(&"food")
		&"turn":
			return state.turn
		&"squads":
			return state.army.count_squads()
		&"royal_squads", &"elite_squads", &"cavalry_squads":
			var count := 0
			for squad in state.army.squads:
				var unit: UnitData = state.units.get(squad.unit_id)
				if what == &"royal_squads":
					count += 1 if unit != null and unit.tier() >= 3 else 0
				elif what == &"elite_squads":
					count += 1 if squad.level() >= 2 else 0
				else:
					count += 1 if unit != null and unit.is_cavalry else 0
			return count
		&"allies":
			return state.alliances.allies().size()
		&"annexed":
			return state.wars.count_annexed()
		&"agreements":
			return state.diplomacy.agreements.size()
		&"agents_on_mission":
			var count := 0
			for agent in state.agents.agents:
				count += 1 if agent.mission != Agent.NO_MISSION else 0
			return count
		&"officers":
			return state.generals.generals.size() + state.advisors.advisors.size()
		&"full_court":
			return 1 if state.generals.generals.size() >= Generals.MAX_GENERALS and state.advisors.is_full() else 0
		&"best_stars", &"best_level", &"limit_breaks":
			var value := 0
			for officer: Officer in _officers(state):
				if what == &"best_stars":
					value = maxi(value, officer.stars)
				elif what == &"best_level":
					value = maxi(value, officer.level)
				else:
					value += officer.breaks
			return value
		&"legendaries":
			return state.equipment.found_legendaries.size()
		&"won":
			return 1 if state.victory.won_path != Victory.NO_PATH else 0
		&"won_difficulty":
			return state.difficulty + 1 if state.victory.won_path != Victory.NO_PATH else 0
		&"won_fast":
			return 1 if state.victory.won_path != Victory.NO_PATH and state.turn <= FAST_WIN_TURN else 0
		&"lost":
			return 1 if state.victory.lost else 0
	push_warning("Unknown achievement measure: %s" % what)
	return 0


static func _officers(state: KingdomState) -> Array[Officer]:
	var result: Array[Officer] = []
	result.append_array(state.generals.generals)
	result.append_array(state.advisors.advisors)
	return result


## Unlocks (AchievementStore) every achievement this game has now reached and returns them, in
## the file's order; also keeps the best progress of the locked ones.
static func check(state: KingdomState) -> Array[Dictionary]:
	var unlocked: Array[Dictionary] = []
	var values := {}
	for entry in all():
		if AchievementStore.is_unlocked(entry.id):
			continue
		if not values.has(entry.measure):
			values[entry.measure] = measure(entry.measure, state)
		var value: int = values[entry.measure]
		if value >= entry.target:
			if AchievementStore.unlock(entry.id):
				unlocked.append(entry)
		elif entry.target > 1 and value > 0:
			AchievementStore.note_progress(entry.id, value)
	return unlocked


## "Màu quân: Đất son", "Danh hiệu: Chiến Thần", "Khung chân dung: Ngọc bích", or "".
static func reward_text(entry: Dictionary) -> String:
	var reward: Dictionary = entry.get("reward", {})
	if reward.has("color"):
		return "Màu quân: " + String(reward.name)
	if reward.has("honor"):
		return "Danh hiệu: " + String(reward.honor)
	if reward.has("frame"):
		return "Khung chân dung chúa công: " + String(reward.name)
	return ""


## Achievements whose reward is of this kind ("color", "honor", "frame"), unlocked or not.
static func with_reward(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in all():
		if entry.reward.has(kind):
			result.append(entry)
	return result


## Rewards of this kind already unlocked: colors as Color, honors and frames as String.
static func unlocked_rewards(kind: String) -> Array:
	var result := []
	for entry in with_reward(kind):
		if AchievementStore.is_unlocked(entry.id):
			result.append(Color.html(entry.reward.color) if kind == "color" else String(entry.reward[kind]))
	return result


## The frame reward's shown name ("Ngọc bích"), or "" for an unknown id.
static func frame_name(frame_id: String) -> String:
	for entry in with_reward("frame"):
		if entry.reward.frame == frame_id:
			return String(entry.reward.name)
	return ""


## Share of all achievements unlocked, 0..1.
static func completion() -> float:
	return float(AchievementStore.count_unlocked()) / maxf(1.0, all().size())
