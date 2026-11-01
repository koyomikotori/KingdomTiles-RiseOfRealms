class_name Notices
extends RefCounted
## What the notice column shows (GDD §15, M14b): what is going on in the kingdom right now and
## what happened at the start of this turn, in three sections of items. Each item has a title
## and detail lines the player can fold away. Resources collected are left out on purpose.
## Pure: built from the state and the last end_turn() report (empty after loading a game).

const SECTIONS: Array[StringName] = [&"buildings", &"diplomacy", &"army"]
const SECTION_TITLES: Dictionary[StringName, String] = {
	&"buildings": "Công trình",
	&"diplomacy": "Ngoại giao",
	&"army": "Quân đội & tướng sĩ",
}


## [{"id", "title", "items": [{"id", "title", "lines": Array[String], "warning": bool}]}]; empty
## items and sections are left out. Item ids are unique within their section.
static func build(state: KingdomState, report: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for section_id in SECTIONS:
		var items: Array[Dictionary] = []
		match section_id:
			&"buildings":
				items = _building_items(state, report)
			&"diplomacy":
				items = _diplomacy_items(state, report)
			&"army":
				items = _army_items(state, report)
		items = items.filter(func(item: Dictionary) -> bool: return not item.lines.is_empty())
		if not items.is_empty():
			result.append({"id": section_id, "title": SECTION_TITLES[section_id], "items": items})
	return result


## "section/item": the key the folded items are remembered by (GameSettings).
static func key(section_id: StringName, item_id: StringName) -> String:
	return "%s/%s" % [section_id, item_id]


static func _item(id: StringName, title: String, lines: Array[String], warning: bool = false) -> Dictionary:
	return {"id": id, "title": "%s (%d)" % [title, lines.size()] if lines.size() > 1 else title, "lines": lines,
			"warning": warning}


static func _building_items(state: KingdomState, report: Dictionary) -> Array[Dictionary]:
	var building: Array[String] = []
	if state.castle_turns > 0:
		building.append("Thành chính lên cấp %d: còn %d lượt" % [state.castle_level + 1, state.castle_turns])
	for origin in state.board.get_construction_origins():
		var cell := state.board.get_cell(origin)
		var data: BuildingData = state.buildings.get(cell.building_id)
		var building_name := data.display_name if data != null else String(cell.building_id)
		if cell.building_upgrading:
			building.append("%s lên cấp %d: còn %d lượt" % [building_name, cell.building_level + 1, cell.building_turns])
		else:
			building.append("%s: còn %d lượt" % [building_name, cell.building_turns])
	var finished: Array[String] = []
	for entry: Dictionary in report.get("completed", []):
		finished.append("%s %s" % [entry.name, "lên cấp %d" % entry.level if entry.upgrade else "đã xây xong"])
	var forge: Array[String] = []
	var forged: Item = report.get("forged")
	if forged != null:
		forge.append("Vừa rèn xong %s (%s)" % [forged.display_name, Item.RARITY_NAMES[forged.rarity]])
	if not state.equipment.forge_job.is_empty():
		forge.append("Đang rèn: còn %d lượt" % state.equipment.forge_job.turns)
	# Put out of work by a war event (M16b): turns left, and those back at work this turn.
	var idle: Array[String] = []
	for cell in state.board.get_all_cells():
		if cell.disabled_turns > 0 and cell.has_building() and cell.coord == cell.building_origin:
			var data: BuildingData = state.buildings.get(cell.building_id)
			idle.append("%s bỏ hoang: còn %d lượt" % [data.display_name if data != null else String(cell.building_id),
					cell.disabled_turns])
	for origin: Vector2i in report.get("back_to_work", []):
		var data: BuildingData = state.buildings.get(state.board.get_cell(origin).building_id)
		if data != null:
			idle.append("%s hoạt động trở lại" % data.display_name)
	var unpaid: Array[String] = []
	if not state.buildings_supplied:
		unpaid.append("Không đủ phí duy trì: công trình tạm ngưng tác dụng lượt này")
	return [_item(&"constructing", "Đang thi công", building), _item(&"completed", "Vừa hoàn thành", finished),
			_item(&"forge", "Xưởng rèn", forge), _item(&"idle", "Bỏ hoang vì chiến sự", idle, true),
			_item(&"upkeep", "Thiếu phí duy trì", unpaid, true)]


static func _diplomacy_items(state: KingdomState, report: Dictionary) -> Array[Dictionary]:
	var clans := state.diplomacy.clans
	var wars: Array[String] = []
	var truces: Array[String] = []
	var allies: Array[String] = []
	for clan_id in _sorted(clans.keys()):
		var front := state.wars.fronts[clan_id]
		var clan_name := clans[clan_id].data.display_name
		if front.annexed:
			continue
		if front.at_war:
			wars.append("%s: quân %d/%d" % [clan_name, front.strength, front.max_strength])
		elif front.truce_turns > 0:
			truces.append("%s: còn %d lượt" % [clan_name, front.truce_turns])
		if clans[clan_id].is_allied():
			allies.append("%s: còn %d lượt" % [clan_name, clans[clan_id].alliance_turns])
	var declared: Array[String] = []
	for clan_id: StringName in report.get("war_declared", []):
		declared.append("%s đã tuyên chiến với vương quốc!" % clans[clan_id].data.display_name)
	var trade: Array[String] = []
	for agreement in state.diplomacy.agreements:
		trade.append("%s: đưa %d %s, nhận %d %s, còn %d lượt" % [clans[agreement.clan_id].data.display_name,
				agreement.give_amount, _resource_name(state, agreement.give_id), agreement.get_amount,
				_resource_name(state, agreement.get_id), agreement.turns_left])
	for entry: Dictionary in report.get("agreements", []):
		var agreement: Diplomacy.Agreement = entry.agreement
		var clan_name: String = clans[agreement.clan_id].data.display_name
		match entry.event:
			&"missed":
				trade.append("Không đủ hàng để giao cho %s (quan hệ −%d)" % [clan_name, Diplomacy.AGREEMENT_MISSED_PENALTY])
			&"cancelled":
				trade.append("%s đã hủy hợp đồng vì quan hệ thù địch" % clan_name)
		if entry.get("completed", false):
			trade.append("Hợp đồng với %s đã hoàn thành" % clan_name)
	var treaty_news: Array[String] = []
	for entry: Dictionary in report.get("treaties", []):
		var clan_name: String = clans[entry.clan_id].data.display_name
		if entry.event == &"alliance_broken":
			treaty_news.append("%s rời bỏ liên minh vì quan hệ đi xuống" % clan_name)
		elif entry.event == &"pact_expired":
			treaty_news.append("Hiệp định bất tương xâm với %s đã hết hạn" % clan_name)
		else:
			treaty_news.append("Liên minh với %s đã hết hạn" % clan_name)
	# Agents (GDD §8 M14e): who is where, then this turn's news.
	var agents: Array[String] = []
	var caught: Array[String] = []
	for entry: Dictionary in report.get("agents", []):
		var clan_name: String = clans[entry.clan_id].data.display_name
		match entry.event:
			&"done":
				agents.append("%s đã xong nhiệm vụ %s ở %s, trở về" % [entry.name,
						Agent.MISSION_NAMES[entry.mission].to_lower(), clan_name])
			&"recalled":
				agents.append("%s trở về vì %s đã sáp nhập vào vương quốc" % [entry.name, clan_name])
			&"caught":
				caught.append("%s bị %s phát hiện và đã trốn về (quan hệ −%d)" % [entry.name, clan_name, -Agents.CAUGHT_RELATION])
			&"killed":
				caught.append("%s bị %s bắt và giết (quan hệ −%d)" % [entry.name, clan_name, -Agents.CAUGHT_RELATION])
	for agent in state.agents.agents:
		if agent.is_busy():
			agents.append("%s: %s ở %s, còn %d lượt" % [agent.name, Agent.MISSION_NAMES[agent.mission].to_lower(),
					clans[agent.target].data.display_name, agent.turns_left])
	return [_item(&"declared", "Vừa bị tuyên chiến", declared, true), _item(&"wars", "Đang chiến tranh", wars, true),
			_item(&"truces", "Đình chiến", truces), _item(&"trade", "Hợp đồng giao thương", trade),
			_item(&"allies", "Đang liên minh", allies), _item(&"treaty_news", "Liên minh thay đổi", treaty_news),
			_item(&"agents_caught", "Đặc vụ bị lộ", caught, true), _item(&"agents", "Đặc vụ", agents)]


static func _army_items(state: KingdomState, report: Dictionary) -> Array[Dictionary]:
	var replenished: Array[String] = []
	var added: Dictionary = report.get("replenished", {})
	for unit_id: StringName in added:
		replenished.append("+%d %s" % [added[unit_id], state.units[unit_id].display_name])
	var deserted: Array[String] = []
	var gone: Dictionary = report.get("deserted", {})
	for unit_id: StringName in gone:
		deserted.append("%d %s bỏ đi vì thiếu lương thực" % [gone[unit_id], state.units[unit_id].display_name])
	var wounded: Array[String] = []
	for officer: Officer in _officers(state):
		if officer.wounded_turns > 0:
			wounded.append("%s: còn %d lượt" % [officer.name, officer.wounded_turns])
	var healed: Array[String] = []
	for key_name in ["generals_healed", "advisors_healed"]:
		for officer: Officer in report.get(key_name, []):
			healed.append("%s đã lành vết thương" % officer.name)
	var candidates: Array[String] = []
	if state.generals.candidates_turn == state.turn and not report.is_empty():
		candidates.append("Có ứng viên mới (thành chính, tab Chiêu hiền)")
	# The uprising and the expedition (GDD §15 M14i).
	var uprising: Array[String] = []
	if state.expedition != null:
		var stage: Dictionary = report.get("expedition", {})
		uprising.append("Đội thảo phạt ở ải %d/%d, đã thắng %d trận" % [mini(state.expedition.stage + 1, state.expedition.stages),
				state.expedition.stages, state.expedition.wins])
		if not stage.is_empty():
			uprising.append("Ải %d vừa đánh xong: bấm vùng đỏ để xem lại trận" % (stage.stage + 1))
	elif state.uprising.is_active():
		uprising.append("Quân nổi loạn chiếm %d ô đất: bấm vùng đỏ để thảo phạt" % state.uprising.cells.size())
	var danger: Array[String] = []
	if report.get("castle_in_danger", false):
		danger.append("Chỉ còn %d ô đất ngoài thành!" % state.board.count_land_outside_castle())
	return [_item(&"danger", "Thành chính nguy hiểm", danger, true), _item(&"uprising", "Thảo phạt", uprising, true),
			_item(&"deserted", "Lính bỏ trốn", deserted, true),
			_item(&"replenished", "Bổ sung quân", replenished), _item(&"wounded", "Tướng sĩ bị thương", wounded),
			_item(&"healed", "Vừa lành vết thương", healed), _item(&"candidates", "Ứng viên mới", candidates)]


static func _officers(state: KingdomState) -> Array[Officer]:
	var result: Array[Officer] = []
	result.append_array(state.generals.generals)
	result.append_array(state.advisors.advisors)
	return result


static var _resource_types: Array[ResourceTypeData] = []


static func _resource_name(_state: KingdomState, resource_id: StringName) -> String:
	if _resource_types.is_empty():
		_resource_types = ResourceTypeData.load_all()
	for type in _resource_types:
		if type.resource_id == resource_id:
			return type.display_name.to_lower()
	return String(resource_id)


static func _sorted(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(ids)
	result.sort()
	return result
