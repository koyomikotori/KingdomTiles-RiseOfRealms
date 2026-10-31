class_name ArmyPanel
extends VBoxContainer
## Army tab (GDD §8, M12d): a long "Tuyển lính" button that opens the RecruitWindow in the middle
## of the screen, the squad room, commander and strategist, one row per unit type the kingdom has
## (sprite, squads and soldiers, total upkeep), then every squad with its level and a disband
## button.

signal recruit_window_requested
signal disband_requested(squad: Army.Squad)

const HEADER_COLOR := UiPalette.HEADER
const WARNING_COLOR := UiPalette.WARNING
const XP_COLOR := UiPalette.XP

var _units: Array[UnitData] = []
var _resource_types: Array[ResourceTypeData] = []
var _summary_label: Label
var _type_list: VBoxContainer
var _squad_list: VBoxContainer


func setup(units: Array[UnitData], resource_types: Array[ResourceTypeData]) -> void:
	_units = units
	_resource_types = resource_types
	add_theme_constant_override("separation", 6)
	var open := Button.new()
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
	_type_list = VBoxContainer.new()
	_type_list.add_theme_constant_override("separation", 4)
	add_child(_type_list)
	add_child(_section_label("Đơn vị của bạn"))
	_squad_list = VBoxContainer.new()
	add_child(_squad_list)


func refresh(state: KingdomState) -> void:
	var upkeep := UiFormat.amounts(state.get_army_upkeep(), _resource_types)
	var replenish := "Tự bổ sung %d%% quân mỗi lượt (doanh trại cấp cao hồi nhanh hơn)." % roundi(state.replenish_fraction() * 100) \
			if state.can_replenish() else "Cần doanh trại để bổ sung quân."
	var commander := state.generals.commander
	var leader := "Tổng tướng: chưa có (tuyển ở thành chính, tab Chiêu hiền)."
	if commander != null:
		leader = "Tổng tướng: %s %s · Võ lực %d · Thống suất %d%s" % [commander.name, commander.star_text(),
				commander.might, commander.command,
				"" if commander.is_ready() else " · đang thảo phạt" if commander.away else " · bị thương, còn %d lượt" % commander.wounded_turns]
	var strategist := "Mưu sĩ Quân sự: chưa có (giao chức ở tab Tướng sĩ)."
	var advisor := state.advisors.holder(&"military")
	if advisor != null:
		strategist = "Mưu sĩ Quân sự: %s %s · Mưu lược %d · %d mưu kế%s" % [advisor.name, advisor.star_text(),
				advisor.strategy, advisor.stratagems.size(),
				"" if advisor.is_ready() else " · đang thảo phạt" if advisor.away else " · bị thương, còn %d lượt" % advisor.wounded_turns]
	_summary_label.text = "Đơn vị: %d/%d · %d lính · Nuôi quân, tướng, mưu sĩ: %s/lượt\n%s\n%s\n%s" % [
			state.army.count_squads(), state.get_squad_capacity(), state.army.count_soldiers(),
			upkeep if not upkeep.is_empty() else "0", replenish, leader, strategist]
	_rebuild_type_list(state)
	_rebuild_squad_list(state)


## One row per unit type the kingdom has: sprite, squads / soldiers and what they eat together.
func _rebuild_type_list(state: KingdomState) -> void:
	for child in _type_list.get_children():
		_type_list.remove_child(child)
		child.queue_free()
	for unit in _units:
		var squads := state.army.count_squads(unit.unit_id)
		if squads == 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_type_list.add_child(row)
		var figure := OfficerFigure.new()
		figure.setup_unit(unit, 2)
		row.add_child(figure)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(column)
		var name_label := Label.new()
		name_label.text = "%s  ×%d" % [unit.display_name, squads]
		name_label.add_theme_color_override("font_color", unit.tier_color(false))
		column.add_child(name_label)
		var eats: Dictionary[StringName, int] = {}
		for resource_id in unit.upkeep:
			eats[resource_id] = unit.upkeep[resource_id] * squads
		column.add_child(_small_label("%d lính · Nuôi: %s/lượt" % [state.army.count_soldiers(unit.unit_id),
				UiFormat.amounts(eats, _resource_types)]))


func _rebuild_squad_list(state: KingdomState) -> void:
	for child in _squad_list.get_children():
		_squad_list.remove_child(child)
		child.queue_free()
	if state.army.squads.is_empty():
		_squad_list.add_child(_small_label("(chưa có đơn vị nào)"))
		return
	for squad in state.army.squads:
		var unit := state.units[squad.unit_id]
		var row := HBoxContainer.new()
		_squad_list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		row.add_child(info)
		var level := squad.level()
		var level_text := Experience.SQUAD_LEVEL_NAMES[level]
		if level > 0:
			level_text = Experience.SQUAD_LEVEL_MARKS[level] + " " + level_text
		var label := _small_label("%s · %s — %d/%d lính%s" % [unit.display_name, level_text, squad.soldiers, unit.squad_size,
				" · đang thảo phạt" if squad.away else ""])
		# Understrength squads show in the warning color, the others in their tier color (M13b).
		label.add_theme_color_override("font_color", WARNING_COLOR if squad.soldiers < unit.squad_size else unit.tier_color(false))
		info.add_child(label)
		info.add_child(_xp_bar(Experience.squad_progress(squad.xp)))
		var button := Button.new()
		button.text = "Giải tán"
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		# Disbanding cannot be undone: the first click asks for confirmation.
		button.pressed.connect(func() -> void:
			if button.text == "Giải tán":
				button.text = "Chắc chắn?"
			else:
				disband_requested.emit(squad))
		button.disabled = squad.away
		row.add_child(button)


## A thin bar showing progress toward the squad's next level.
func _xp_bar(progress: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = XP_COLOR
	var background := StyleBoxFlat.new()
	background.bg_color = UiPalette.BAR_BACKGROUND
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	return bar


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADER_COLOR)
	return label


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	return label
