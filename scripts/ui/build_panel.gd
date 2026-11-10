class_name BuildPanel
extends VBoxContainer
## Build tab (GDD §8, M12d): a long "Xây dựng công trình" button that opens the BuildWindow in the
## middle of the screen, the castle level, the builder teams, then one row per building type the
## kingdom has: picture, count / limit (foundations included) and the type's total upkeep.
## Everything about one building (upgrade, move, demolish) is in its BuildingWindow, opened by
## tapping it on the board.

signal build_window_requested

## The long button on top (the tutorial points at it, M18a).
var open_button: Button

const MUTED_COLOR := UiPalette.MUTED
const WARNING_COLOR := UiPalette.WARNING
## Size of the building pictures in the rows.
const ICON_SIZE := 40

var _buildings: Dictionary[StringName, BuildingData] = {}
var _resource_types: Array[ResourceTypeData] = []
var _castle_label: Label
var _builders_label: Label
var _rows: VBoxContainer


func setup(buildings: Dictionary[StringName, BuildingData], resource_types: Array[ResourceTypeData]) -> void:
	_buildings = buildings
	_resource_types = resource_types
	add_theme_constant_override("separation", 6)
	open_button = Button.new()
	var open := open_button
	open.text = "Xây dựng công trình"
	open.focus_mode = Control.FOCUS_NONE
	open.custom_minimum_size = Vector2(0, 44)
	open.pressed.connect(func() -> void: build_window_requested.emit())
	add_child(open)
	_castle_label = _label("", 15)
	add_child(_castle_label)
	_builders_label = _label("", 13)
	add_child(_builders_label)
	add_child(_label("Bấm vào công trình trên bản đồ để nâng cấp, di chuyển hoặc phá hủy.", 12))
	add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)


func refresh(state: KingdomState) -> void:
	var castle := "Thành chính cấp %d/%d" % [state.castle_level, state.castle_levels.size()]
	if state.castle_turns > 0:
		castle += " · đang nâng cấp, còn %d lượt" % state.castle_turns
	_castle_label.text = castle
	_builders_label.text = "Đội thợ: %d/%d đang làm" % [state.builders_busy(), state.builder_limit()]
	_builders_label.add_theme_color_override("font_color", WARNING_COLOR if not state.has_free_builder() else MUTED_COLOR)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ids := _buildings.keys().filter(func(id: StringName) -> bool: return state.board.count_buildings(id, true) > 0)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _buildings[a].display_name < _buildings[b].display_name)
	if ids.is_empty():
		_rows.add_child(_label("(chưa có công trình nào)", 12))
	for building_id: StringName in ids:
		_rows.add_child(_row(state, _buildings[building_id]))


## Picture, name with count / limit, then the foundations still being built and the total upkeep.
func _row(state: KingdomState, building: BuildingData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var picture := TextureRect.new()
	picture.texture = GameArt.building(building.building_id)
	picture.custom_minimum_size = Vector2.ONE * ICON_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	var total := state.board.count_buildings(building.building_id, true)
	var most := BuildRules.limit(building, state.castle_level)
	column.add_child(_label("%s  %d/%d" % [building.display_name, total, most] if most > 0
			else "%s  %d" % [building.display_name, total], 14))
	var details: Array[String] = []
	var unfinished := total - state.board.count_buildings(building.building_id)
	if unfinished > 0:
		details.append("%d đang thi công" % unfinished)
	var upkeep := UiFormat.amounts(state.building_type_upkeep(building.building_id), _resource_types)
	details.append("Duy trì: %s/lượt" % upkeep if not upkeep.is_empty() else "Không tốn phí duy trì")
	column.add_child(_label(" · ".join(details), 12))
	return row


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if font_size < 14:
		label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
