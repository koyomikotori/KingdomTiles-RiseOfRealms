class_name ImportantNews
extends RefCounted
## The start-of-turn news that cannot wait in the notice column (GDD §15, M14g): wars declared,
## agents caught, the commander or the military advisor hurt in the turn's battle, deserters,
## allies leaving, the castle in danger. Shown in ImportantReportWindow after the turn's battle
## and before the events. Pure: built from the state, the end_turn() report and the result of the
## turn's raid or invasion (empty when there was none).


## [{"title", "lines": Array[String]}]; empty when nothing important happened.
static func build(state: KingdomState, report: Dictionary, battle: Dictionary = {}) -> Array[Dictionary]:
	var clans := state.diplomacy.clans
	var result: Array[Dictionary] = []
	var declared: Array[String] = []
	for clan_id: StringName in report.get("war_declared", []):
		declared.append("%s đã tuyên chiến với vương quốc!" % clans[clan_id].data.display_name)
	_add(result, "Bị tuyên chiến", declared)

	var agents: Array[String] = []
	for entry: Dictionary in report.get("agents", []):
		var clan_name: String = clans[entry.clan_id].data.display_name
		match entry.event:
			&"caught":
				agents.append("Đặc vụ %s bị %s phát hiện, đã trốn về (quan hệ −%d)." % [entry.name, clan_name,
						-Agents.CAUGHT_RELATION])
			&"killed":
				agents.append("Đặc vụ %s bị %s bắt và giết (quan hệ −%d)." % [entry.name, clan_name, -Agents.CAUGHT_RELATION])
	_add(result, "Đặc vụ bị lộ", agents)

	var officers: Array[String] = []
	var general: Dictionary = battle.get("general", {})
	match general.get("fate", &"none"):
		&"dead":
			officers.append("Tổng tướng %s đã tử trận, mất luôn trang bị đang đeo!" % general.name)
		&"wounded":
			officers.append("Tổng tướng %s bị thương, nghỉ %d lượt." % [general.name, Generals.WOUND_TURNS])
	var advisor: Dictionary = battle.get("advisor", {})
	if advisor.get("fate", &"none") == &"wounded":
		officers.append("Mưu sĩ %s bị thương, nghỉ %d lượt." % [advisor.name, Advisors.WOUND_TURNS])
	_add(result, "Tướng sĩ", officers)

	var deserted: Array[String] = []
	var gone: Dictionary = report.get("deserted", {})
	for unit_id: StringName in gone:
		deserted.append("%d %s bỏ đi vì thiếu lương thực." % [gone[unit_id], state.units[unit_id].display_name])
	_add(result, "Lính đào ngũ", deserted)

	var allies: Array[String] = []
	for entry: Dictionary in report.get("treaties", []):
		if entry.event == &"alliance_broken":
			allies.append("%s rời bỏ liên minh vì quan hệ đi xuống." % clans[entry.clan_id].data.display_name)
	_add(result, "Đồng minh rời bỏ", allies)

	var expedition: Dictionary = report.get("expedition", {})
	var expedition_lines: Array[String] = []
	if report.get("uprising", &"") == &"started":
		expedition_lines.append("Đạo tặc nổi loạn chiếm %d ô đất của vương quốc: công trình ở đó ngừng hoạt động. Bấm vào vùng đỏ để thảo phạt." %
				state.uprising.cells.size())
	match expedition.get("general_fate", &"none"):
		&"dead":
			expedition_lines.append("Tướng dẫn đội thảo phạt đã tử trận!")
		&"wounded":
			expedition_lines.append("Tướng dẫn đội thảo phạt bị thương, nghỉ %d lượt." % Generals.WOUND_TURNS)
	_add(result, "Nổi loạn", expedition_lines)

	if report.get("castle_in_danger", false):
		_add(result, "Thành chính nguy hiểm", ["Chỉ còn %d ô đất ngoài thành: mất hết là thua!" %
				state.board.count_land_outside_castle()] as Array[String])
	return result


static func _add(result: Array[Dictionary], title: String, lines: Array[String]) -> void:
	if not lines.is_empty():
		result.append({"title": title, "lines": lines})
