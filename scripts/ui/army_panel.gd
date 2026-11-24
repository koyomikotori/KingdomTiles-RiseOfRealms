class_name ArmyPanel
extends VBoxContainer
## Army tab (GDD §8, M12d; regrouped in M18f-b1b, GDD §35b): a long "Tuyển lính" button that opens
## the RecruitWindow in the middle of the screen, the squad room, commander and strategist, then the
## squads in folding groups: "Ở nhà", one per realm army (general, town) and the expedition.
## Inside a group the squads are folded by unit type (icon, count, soldiers out of full, a strength
## bar); opening a type lists its squads with their level, XP and, at home, a disband button. Only
## the home group starts open; what is open is kept while the game runs.

signal recruit_window_requested

## The long button on top (the tutorial points at it, M18a).
var open_button: Button
signal disband_requested(squad: Army.Squad)

const HEADER_COLOR := UiPalette.HEADER
const WARNING_COLOR := UiPalette.WARNING
const XP_COLOR := UiPalette.XP
const HOME_GROUP := "home"
const EXPEDITION_GROUP := "expedition"
const ICON_SIZE := 28
const INDENT := 14

var _units: Array[UnitData] = []
var _resource_types: Array[ResourceTypeData] = []
var _summary_label: Label
var _groups: VBoxContainer
var _state: KingdomState
## Group key -> open; group key + "/" + unit id -> open.
var _open: Dictionary = {HOME_GROUP: true}


func setup(units: Array[UnitData], resource_types: Array[ResourceTypeData]) -> void:
	_units = units
	_resource_types = resource_types
	add_theme_constant_override("separation", 6)
	open_button = Button.new()
	var open := open_button
	open.text = "Tuyển lính"
	open.focus_mode = Control.FOCUS_NONE
	open.custom_minimum_size = Vector2(0, 44)
	open.pressed.connect(func() -> void: recruit_window_requested.emit())
	add_child(open)
	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", 13)
	add_child(_summary_label)
	add_child(HSeparator.new())
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 4)
	add_child(_groups)


func refresh(state: KingdomState) -> void:
	_state = state
	var upkeep := UiFormat.amounts(state.get_army_upkeep(), _resource_types)
	var replenish := "Tự bổ sung %d%% quân mỗi lượt (doanh trại cấp cao hồi nhanh hơn)." % roundi(state.replenish_fraction() * 100) \
			if state.can_replenish() else "Cần doanh trại để bổ sung quân."
	var commander := state.generals.commander
	var leader := "Tổng tướng: chưa có (tuyển ở thành chính, tab Chiêu hiền)."
	if commander != null:
		leader = "Tổng tướng: %s %s · Võ lực %d · Thống suất %d%s" % [commander.name, commander.star_text(),
				commander.might, commander.command,
				"" if commander.is_ready() else " · " + commander.away_text() if commander.away else " · bị thương, còn %d lượt" % commander.wounded_turns]
	var stand_in := state.generals.stand_in()
	if stand_in != null:
		leader += "\nTạm chỉ huy ở nhà: %s %s" % [stand_in.name, stand_in.star_text()]
	if state.can_replenish():
		replenish += " Huấn luyện +%d kinh nghiệm mỗi lượt, tới %s." % [roundi(state.training_xp()),
				Experience.SQUAD_LEVEL_NAMES.back() if state.elite_training()
				else Experience.SQUAD_LEVEL_NAMES[Experience.TRAINING_MAX_LEVEL]]
	var strategist := "Mưu sĩ Quân sự: chưa có (giao chức ở tab Tướng sĩ)."
	var advisor := state.advisors.holder(&"military")
	if advisor != null:
		strategist = "Mưu sĩ Quân sự: %s %s · Mưu lược %d · %d mưu kế%s" % [advisor.name, advisor.star_text(),
				advisor.strategy, advisor.stratagems.size(),
				"" if advisor.is_ready() else " · " + advisor.away_text() if advisor.away else " · bị thương, còn %d lượt" % advisor.wounded_turns]
	_summary_label.text = "Đơn vị: %d/%d · %d lính · Nuôi quân, tướng, mưu sĩ: %s/lượt\n%s\n%s\n%s" % [
			state.army.count_squads(), state.get_squad_capacity(), state.army.count_soldiers(),
			upkeep if not upkeep.is_empty() else "0", replenish, leader, strategist]
	_rebuild()


## Every group of squads: {key, title, squads}. Home first, then each realm army, then the
## squads away on an expedition (away but in no army).
static func groups_of(state: KingdomState) -> Array[Dictionary]:
	var home: Array[Army.Squad] = []
	var in_armies := {}
	var result: Array[Dictionary] = []
	if state.realm.active:
		for force in state.realm.forces:
			for squad in force.squads:
				in_armies[squad] = true
	var expedition: Array[Army.Squad] = []
	for squad in state.army.squads:
		if not squad.away:
			home.append(squad)
		elif not in_armies.has(squad):
			expedition.append(squad)
	result.append({"key": HOME_GROUP, "title": "Ở nhà", "squads": home})
	if state.realm.active:
		for force in state.realm.forces:
			var general := force.general
			var title := "Đạo quân %s %s · %s" % [general.name if general != null else "?",
					general.star_text() if general != null else "", state.realm.towns[force.town].name]
			result.append({"key": "force:%d" % force.get_instance_id(), "title": title, "squads": force.squads})
	if not expedition.is_empty():
		result.append({"key": EXPEDITION_GROUP, "title": "Đang thảo phạt", "squads": expedition})
	return result


func _rebuild() -> void:
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	if _state.army.squads.is_empty():
		_groups.add_child(_small_label("(chưa có đơn vị nào)"))
		return
	for group in groups_of(_state):
		_add_group(group)


func _add_group(group: Dictionary) -> void:
	var key: String = group.key
	var squads: Array = group.squads
	if squads.is_empty() and key != HOME_GROUP:
		return
	var soldiers := 0
	var full := 0
	for squad: Army.Squad in squads:
		soldiers += squad.soldiers
		full += _state.units[squad.unit_id].squad_size
	var is_open: bool = _open.get(key, false)
	var header := _fold_button("%s %s" % ["▾" if is_open else "▸", group.title],
			"%d đơn vị · %d/%d lính" % [squads.size(), soldiers, full], HEADER_COLOR, null)
	header.pressed.connect(_toggle.bind(key))
	_groups.add_child(header)
	if not is_open:
		return
	if squads.is_empty():
		_groups.add_child(_indented(_small_label("(không còn đơn vị nào ở nhà)"), 1))
		return
	for unit in _units:
		var of_type: Array[Army.Squad] = []
		for squad: Army.Squad in squads:
			if squad.unit_id == unit.unit_id:
				of_type.append(squad)
		if not of_type.is_empty():
			_add_type(key, unit, of_type)


## One folding row per unit type in a group: icon, name ×count, soldiers / full and a strength bar.
func _add_type(group_key: String, unit: UnitData, squads: Array[Army.Squad]) -> void:
	var key := "%s/%s" % [group_key, unit.unit_id]
	var soldiers := 0
	for squad in squads:
		soldiers += squad.soldiers
	var full := unit.squad_size * squads.size()
	var is_open: bool = _open.get(key, false)
	var button := _fold_button("%s %s" % ["▾" if is_open else "▸", unit.display_name],
			"×%d · %d/%d" % [squads.size(), soldiers, full], unit.tier_color(false), unit)
	button.pressed.connect(_toggle.bind(key))
	button.tooltip_text = "%s: %d đơn vị, %d/%d lính. Bấm để %s." % [unit.display_name, squads.size(), soldiers, full,
			"thu gọn" if is_open else "xem từng đơn vị"]
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.add_child(button)
	column.add_child(_bar(float(soldiers) / full, UiPalette.GOOD if soldiers >= full else WARNING_COLOR))
	_groups.add_child(_indented(column, 1))
	if not is_open:
		return
	for squad in squads:
		_groups.add_child(_indented(_squad_row(unit, squad, group_key == HOME_GROUP), 2))


func _squad_row(unit: UnitData, squad: Army.Squad, at_home: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	var level := squad.level()
	var level_text := Experience.SQUAD_LEVEL_NAMES[level]
	if level > 0:
		level_text = Experience.SQUAD_LEVEL_MARKS[level] + " " + level_text
	var label := _small_label("%s — %d/%d lính" % [level_text, squad.soldiers, unit.squad_size])
	# Understrength squads show in the warning color (M13b).
	label.add_theme_color_override("font_color", WARNING_COLOR if squad.soldiers < unit.squad_size else UiPalette.TEXT)
	info.add_child(label)
	info.add_child(_bar(Experience.squad_progress(squad.xp), XP_COLOR))
	if at_home:
		var button := Button.new()
		button.text = "Giải tán"
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		# Disbanding cannot be undone: the kingdom scene asks in a confirmation window (GDD §34).
		button.pressed.connect(func() -> void: disband_requested.emit(squad))
		row.add_child(button)
	return row


func _toggle(key: String) -> void:
	_open[key] = not _open.get(key, false)
	_rebuild()


## A flat full-width button holding a row: the unit's icon if any, `text` (clipped) on the left
## in `color`, `count` on the right.
func _fold_button(text: String, count: String, color: Color, unit: UnitData) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, ICON_SIZE + 4 if unit != null else 30)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 2
	row.offset_right = -4
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unit != null:
		row.add_child(ArmyDetailWindow.unit_icon(unit, ICON_SIZE))
	var name_label := Label.new()
	name_label.text = text
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14 if unit == null else 13)
	name_label.add_theme_color_override("font_color", color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var right := Label.new()
	right.text = count
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_theme_font_size_override("font_size", 12)
	right.add_theme_color_override("font_color", UiPalette.MUTED)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	button.add_child(row)
	return button


func _indented(control: Control, depth: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", INDENT * depth)
	margin.add_child(control)
	return margin


## A thin bar filled to `progress` (0..1).
func _bar(progress: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(progress, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var background := StyleBoxFlat.new()
	background.bg_color = UiPalette.BAR_BACKGROUND
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	return label
