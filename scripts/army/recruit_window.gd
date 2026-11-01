class_name RecruitWindow
extends CatalogWindow
## The "Tuyển lính" shop (GDD §8, M12d / M13 / M13b): unit types by kind (Tất cả / Kiếm / Thương /
## Đao thuẫn / Kỵ binh / Cung / Nỏ / Hỏa khí) with their sprite, stats, special rules, cost, upkeep
## and the buildings they need. Names are colored by tier; types whose buildings are missing are
## faded. Recruiting is instant; the window stays open to recruit more.
const FIGURE_SCALE := 5

var _state: KingdomState
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()


func open(state: KingdomState) -> void:
	_state = state
	var categories: Array[String] = ["Tất cả"]
	categories.append_array(UnitData.TYPE_NAMES)
	build_catalog("Tuyển lính", categories, "Tuyển")
	state.stockpile.changed.connect(refresh)
	state.army.changed.connect(refresh)


func _entries(index: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _state.units:
		if index == 0 or int(_state.units[id].unit_type) == index - 1:
			ids.append(id)
	return ids


func _entry_icon(id: StringName) -> Texture2D:
	var sheet := GameArt.unit_sheet(_state.units[id].get_sprite_id())
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = GameArt.unit_frame(sheet, &"stand", 0)
	return atlas


func _entry_color(id: StringName) -> Color:
	return _state.units[id].tier_color(true)


func _title_color(id: StringName) -> Color:
	return _state.units[id].tier_color(false)


func _entry_dimmed(id: StringName) -> bool:
	return not RecruitmentRules.missing_buildings(_state.board, _state.units[id]).is_empty()


func _entry_name(id: StringName) -> String:
	return _state.units[id].display_name


func _entry_text(id: StringName) -> String:
	return "%s  ×%d" % [_entry_name(id), _state.army.count_squads(id)]


func _picture(id: StringName) -> Control:
	var figure := OfficerFigure.new()
	figure.setup_unit(_state.units[id], FIGURE_SCALE)
	return figure


func _entry_details(id: StringName) -> String:
	var unit := _state.units[id]
	var lines: Array[String] = [
		"%s · %s · %d lính/đơn vị · Sĩ khí %d" % [UnitData.ROW_NAMES[unit.row], UnitData.ATTACK_KIND_NAMES[unit.attack_kind],
				unit.squad_size, unit.morale],
		"Cận chiến %d · Phòng thủ %d · Giáp %d · Xung kích %d" % [unit.melee_attack, unit.melee_defense, unit.armor,
				unit.charge_attack],
	]
	if unit.attack_kind == UnitData.AttackKind.BOW:
		lines.append("Bắn xa %d · Nạp tên %s giây" % [unit.range_attack, str(unit.reload_time)])
	elif unit.attack_kind == UnitData.AttackKind.GUN:
		lines.append("Bắn xa %d · Chỉ nã 1 loạt đầu trận%s" % [unit.range_attack,
				", trúng mọi hàng" if unit.volley_all_rows else ""])
	var special := _special_rules(unit)
	if special != "":
		lines.append(special)
	lines.append("Đang có %d đơn vị · %d lính." % [_state.army.count_squads(id), _state.army.count_soldiers(id)])
	return "\n".join(lines)


func _fill_requirements(id: StringName, view: RequirementView) -> void:
	var unit := _state.units[id]
	view.header("Yêu cầu")
	for building_id in unit.required_buildings:
		var needed: Dictionary[StringName, int] = {building_id: unit.required_buildings[building_id]}
		view.requirement(RecruitmentRules.describe_buildings(needed, _state.buildings),
				_state.board.highest_building_level(building_id) >= needed[building_id])
	for terrain_id in unit.required_terrain:
		var terrain: TerrainData = _state.terrains.get(terrain_id)
		var owned := _state.board.count_owned_terrain(terrain_id)
		view.requirement("%d ô %s (đang có %d)" % [unit.required_terrain[terrain_id],
				terrain.display_name if terrain != null else String(terrain_id), owned], owned >= unit.required_terrain[terrain_id])
	view.requirement("Còn chỗ cho đơn vị (%d/%d)" % [_state.army.count_squads(), _state.get_squad_capacity()],
			_state.army.count_squads() < _state.get_squad_capacity())
	view.header("Chi phí")
	view.costs(unit.recruit_cost, _state.stockpile)
	view.amounts("Nuôi mỗi lượt:", unit.upkeep)


## The unit's own battle rules (GDD §8, M13), or "".
func _special_rules(unit: UnitData) -> String:
	var parts: Array[String] = []
	if unit.is_cavalry:
		parts.append("Kỵ binh: xung kích mạnh, sợ thương binh")
	if unit.charge_resist > 0.0:
		parts.append("Chống xung kích %d%%, đánh mạnh hơn vào kỵ binh" % roundi(unit.charge_resist * 100))
	if unit.armor_pierce > 0.0:
		parts.append("Xuyên giáp %d%%" % roundi(unit.armor_pierce * 100))
	if unit.melee_after_volley:
		parts.append("Bắn xong tiến lên hàng trước cận chiến")
	if unit.charge_after_volleys > 0:
		parts.append("Bắn %d loạt rồi xông vào cận chiến" % unit.charge_after_volleys)
	if unit.steadfast:
		parts.append("Tĩnh tâm: không mất nhuệ khí khi tướng ngã, miễn nhiễm mưu kế hạ nhuệ khí")
	return " · ".join(parts)


func _block_reason(id: StringName) -> String:
	var unit := _state.units[id]
	var result := RecruitmentRules.check(_state.board, _state.stockpile, _state.army, _state.get_squad_capacity(), unit)
	return "" if result == RecruitmentRules.Result.OK else RecruitmentRules.describe(result, unit, _state.buildings, _state.terrains)


func _on_action(id: StringName) -> void:
	var unit := _state.units[id]
	var result := _state.recruit(id)
	if result == RecruitmentRules.Result.OK:
		set_status("Đã tuyển 1 đơn vị %s (+%d lính)." % [unit.display_name, unit.squad_size])
		Sfx.play(&"recruit")
	else:
		set_status(RecruitmentRules.describe(result, unit, _state.buildings, _state.terrains), false)
	refresh()
