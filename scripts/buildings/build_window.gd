class_name BuildWindow
extends CatalogWindow
## The "Xây dựng công trình" shop (GDD §8, M12d): buildings by category (Tất cả / Sản xuất /
## Quân sự / Hành chính) with their picture, use, cost and build time. "Xây dựng" closes it and
## lets the player lay the foundation on the board (kingdom scene, build mode).

signal building_chosen(building_id: StringName)

const PICTURE_SCALE := 6

var _state: KingdomState
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()


func open(state: KingdomState) -> void:
	_state = state
	var categories: Array[String] = ["Tất cả"]
	categories.append_array(BuildingData.CATEGORY_NAMES)
	build_catalog("Xây dựng công trình", categories, "Xây dựng")
	state.stockpile.changed.connect(refresh)


func _entries(index: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _state.buildings:
		if index == 0 or _state.buildings[id].category == index - 1:
			ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var first := _state.buildings[a]
		var second := _state.buildings[b]
		if first.required_castle_level != second.required_castle_level:
			return first.required_castle_level < second.required_castle_level
		return first.display_name < second.display_name)
	return ids


func _entry_icon(id: StringName) -> Texture2D:
	return GameArt.building(id)


func _entry_name(id: StringName) -> String:
	return _state.buildings[id].display_name


func _entry_text(id: StringName) -> String:
	var building := _state.buildings[id]
	if _state.castle_level < building.required_castle_level:
		return "%s (thành cấp %d)" % [building.display_name, building.required_castle_level]
	var most := BuildRules.limit(building, _state.castle_level)
	return "%s  %d/%d" % [building.display_name, _state.board.count_buildings(id, true), most] if most > 0 \
			else building.display_name


func _picture(id: StringName) -> Control:
	var picture := TextureRect.new()
	picture.texture = GameArt.building(id)
	if picture.texture != null:
		picture.custom_minimum_size = picture.texture.get_size() * PICTURE_SCALE / maxf(1.0, _state.buildings[id].size.x)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return picture


func _entry_details(id: StringName) -> String:
	var building := _state.buildings[id]
	var lines: Array[String] = [building.description]
	if building.is_upgradable():
		lines.append("Nâng được tới cấp %d (không vượt cấp thành)." % building.max_level())
	return "\n".join(lines)


func _fill_requirements(id: StringName, view: RequirementView) -> void:
	var building := _state.buildings[id]
	view.header("Yêu cầu")
	var terrains: Array[String] = []
	for terrain_id in building.allowed_terrains:
		var terrain: TerrainData = _state.terrains.get(terrain_id)
		terrains.append(terrain.display_name if terrain != null else String(terrain_id))
	if not terrains.is_empty():
		view.note("Xây trên ô %s." % " / ".join(terrains))
	if building.required_castle_level > 1:
		view.requirement("Thành chính cấp %d (đang cấp %d)" % [building.required_castle_level, _state.castle_level],
				_state.castle_level >= building.required_castle_level)
	var most := BuildRules.limit(building, _state.castle_level)
	if most > 0:
		var count := _state.board.count_buildings(id, true)
		view.requirement("Còn chỗ xây (%d/%d)" % [count, most], count < most)
	view.requirement("Có đội thợ rảnh (%d/%d đang làm)" % [_state.builders_busy(), _state.builder_limit()],
			_state.has_free_builder())
	view.header("Chi phí")
	view.costs(_state.building_cost(building), _state.stockpile)
	view.line(&"time", "%d lượt (chưa hoạt động khi đang xây)" % building.build_turns)
	var produced := building.yields_at(1)
	var effects := building.effect_lines(1)
	if not produced.is_empty() or not effects.is_empty():
		view.header("Cấp 1 nhận được")
		view.amounts("Mỗi lượt:", produced, true)
		for effect in effects:
			view.gain(effect)
	if not building.upkeep.is_empty():
		view.header("Phí duy trì")
		view.amounts("Mỗi lượt:", building.upkeep)


func _block_reason(id: StringName) -> String:
	var building := _state.buildings[id]
	var result := BuildRules.check_type(_state.board, building, _state.castle_level, _state.has_free_builder())
	if result == BuildRules.Result.OK and not _state.stockpile.can_afford(_state.building_cost(building)):
		result = BuildRules.Result.CANNOT_AFFORD
	return "" if result == BuildRules.Result.OK else BuildRules.describe(result)


func _on_action(id: StringName) -> void:
	building_chosen.emit(id)
	close()
