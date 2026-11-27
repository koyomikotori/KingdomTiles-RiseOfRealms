class_name ArmyDialog
extends ModalWindow
## Forms an army at the kingdom's capital, or regroups one standing there (GDD §33, M18f-a; laid
## out again in GDD §35b): general cards with portraits on top (the kingdom's commander marked
## "Tổng tướng", a line on who leads the home battles once the chosen general leaves; fixed when
## regrouping), then unit-type tabs ("Tất cả", one per type at home, "Đã chọn") over a grid of
## squad tiles (icon, soldiers, level) chosen by clicking, "Chọn hết / Bỏ hết" for the shown tab,
## and the chosen squads as a strip of icons with the count. Up to Realm.MAX_ARMY_SQUADS squads
## from those at home (and the army's own).

signal done

## Most height the squad list takes (it gets less on a short screen: ModalWindow.flex).
const SQUAD_LIST_HEIGHT := 420.0
const WIDTH := 0.62
const GENERAL_PORTRAIT := 0.5
const TILE_SIZE := Vector2(126, 92)
const TILE_ICON := 32
const STRIP_ICON := 24
const GRID_COLUMNS := 5
## Tab keys besides unit types (UnitData.Type values).
const ALL := -1
const CHOSEN := -2

var _state: KingdomState
var _force: Realm.Force
var _general: General
var _general_cards: Dictionary = {}  # Button -> General
var _home_line: Label
var _squads: Array[Army.Squad] = []
var _selected: Dictionary = {}  # Army.Squad -> true
var _tab := ALL
var _tab_bar: HFlowContainer
var _grid: GridContainer
var _count: Label
var _strip: HFlowContainer


## `force` null forms a new army.
func open(state: KingdomState, force: Realm.Force = null) -> void:
	_state = state
	_force = force
	var body := build_frame("Lập đạo quân" if force == null else "Điều chỉnh đạo quân %s" % force.general.name,
			UiPalette.ACCENT, WIDTH)
	body.add_child(_header("Tướng dẫn quân"))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 6)
	body.add_child(cards)
	var generals: Array[General] = []
	if force == null:
		generals.assign(state.generals.generals)
	else:
		generals.append(force.general)
		_general = force.general
	for general in generals:
		cards.add_child(_general_card(general))
	if generals.is_empty():
		body.add_child(_label("Chưa có tướng nào. Chiêu hiền ở thành chính.", 14))
	_home_line = _label("", 13)
	_home_line.add_theme_color_override("font_color", UiPalette.MUTED)
	body.add_child(_home_line)
	body.add_child(HSeparator.new())
	body.add_child(_header("Đơn vị theo đạo"))
	for squad in state.army.squads:
		var mine := force != null and force.squads.has(squad)
		if squad.away and not mine:
			continue
		_squads.append(squad)
		if mine:
			_selected[squad] = true
	_squads.sort_custom(_before)
	_tab_bar = HFlowContainer.new()
	_tab_bar.add_theme_constant_override("h_separation", 4)
	_tab_bar.add_theme_constant_override("v_separation", 4)
	body.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	body.add_child(scroll)
	# The squad list takes whatever height the screen leaves, so only it scrolls, never the window.
	flex(scroll, SQUAD_LIST_HEIGHT)
	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 8)
	bulk.add_child(_button("Chọn hết mục này", _select_shown.bind(true)))
	bulk.add_child(_button("Bỏ hết mục này", _select_shown.bind(false)))
	_count = _label("", 15, false)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bulk.add_child(_count)
	body.add_child(bulk)
	_strip = HFlowContainer.new()
	_strip.add_theme_constant_override("h_separation", 2)
	body.add_child(_strip)
	add_action("Lập đạo quân" if force == null else "Cập nhật", _confirm)
	_refresh()


## A toggle card for `general`: portrait, name and stars, might / command, "Tổng tướng" for the
## kingdom's commander, and why it cannot go.
func _general_card(general: General) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(250, 0)
	card.disabled = _force == null and not general.is_ready()
	card.button_pressed = general == _general
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	var portrait := PortraitView.new()
	portrait.setup(general, GENERAL_PORTRAIT, _state.player_color)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_on_wood("%s %s" % [general.name, general.star_text()], 14, UiPalette.ON_WOOD))
	info.add_child(_on_wood("Võ %d · Thống %d" % [general.total_might(), general.total_command()], 12,
			UiPalette.ON_WOOD_MUTED))
	if general == _state.generals.commander:
		info.add_child(_on_wood("♛ Tổng tướng", 12, UiPalette.GOLD))
	if card.disabled:
		info.add_child(_on_wood(general.away_text() if general.away else "Bị thương, còn %d lượt" % general.wounded_turns,
				12, UiPalette.WARNING_ON_WOOD))
	for child in info.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	card.add_child(row)
	card.custom_minimum_size.y = 48 * GENERAL_PORTRAIT * 2 + 12
	card.pressed.connect(_pick_general.bind(general, card))
	_general_cards[card] = general
	if _force != null:
		card.disabled = true
		card.button_pressed = true
	return card


func _pick_general(general: General, pressed: Button) -> void:
	_general = general
	for card: Button in _general_cards:
		card.set_pressed_no_signal(card == pressed)
	_refresh()


## Who leads the home battles once `_general` marches out: the commander, or the ready general
## with the most stars besides the one leaving.
func _home_leader_text() -> String:
	if _force != null:
		return ""
	if _general == null:
		return "Chọn một tướng. Tổng tướng đi thì tướng ở nhà nhiều sao nhất tạm chỉ huy quân giữ nhà."
	var commander := _state.generals.commander
	if _general != commander and commander != null and commander.is_ready():
		return "Tổng tướng %s vẫn ở nhà chỉ huy quân giữ nhà." % commander.name
	var best: General = null
	for general in _state.generals.generals:
		if general != _general and general.is_ready() and (best == null or general.stars > best.stars):
			best = general
	if best == null:
		return "⚠ Không còn tướng nào ở nhà: quân giữ nhà đánh không có tướng."
	return "%s sẽ tạm chỉ huy quân giữ nhà." % [best.name + " " + best.star_text()]


## Unit order first, then the best and fullest squads.
func _before(a: Army.Squad, b: Army.Squad) -> bool:
	var ia := _unit_index(a.unit_id)
	var ib := _unit_index(b.unit_id)
	if ia != ib:
		return ia < ib
	if a.level() != b.level():
		return a.level() > b.level()
	return a.soldiers > b.soldiers


func _unit_index(unit_id: StringName) -> int:
	return _state.units.keys().find(unit_id)


func _type_of(squad: Army.Squad) -> int:
	return _state.units[squad.unit_id].unit_type


func _shown() -> Array[Army.Squad]:
	var result: Array[Army.Squad] = []
	for squad in _squads:
		if _tab == ALL or (_tab == CHOSEN and _selected.has(squad)) or _type_of(squad) == _tab:
			result.append(squad)
	return result


func _show_tab(tab: int) -> void:
	_tab = tab
	_refresh()


func _toggle(squad: Army.Squad) -> void:
	if _selected.has(squad):
		_selected.erase(squad)
	else:
		_selected[squad] = true
	_refresh()


func _select_shown(on: bool) -> void:
	for squad in _shown():
		if on:
			_selected[squad] = true
		else:
			_selected.erase(squad)
	_refresh()


func _chosen() -> Array[Army.Squad]:
	var result: Array[Army.Squad] = []
	for squad in _squads:
		if _selected.has(squad):
			result.append(squad)
	return result


func _refresh() -> void:
	_home_line.text = _home_leader_text()
	_home_line.visible = _home_line.text != ""
	_fill_tabs()
	_fill_grid()
	var chosen := _chosen()
	var soldiers := 0
	for squad in chosen:
		soldiers += squad.soldiers
	set_preview(_count, "Đã chọn %d/%d đơn vị · %d lính" % [chosen.size(), Realm.MAX_ARMY_SQUADS, soldiers],
			chosen.size() <= Realm.MAX_ARMY_SQUADS)
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	for squad in chosen:
		var icon := ArmyDetailWindow.unit_icon(_state.units[squad.unit_id], STRIP_ICON)
		icon.tooltip_text = _state.units[squad.unit_id].display_name
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_strip.add_child(icon)


func _fill_tabs() -> void:
	for child in _tab_bar.get_children():
		_tab_bar.remove_child(child)
		child.queue_free()
	var counts := {}
	for squad in _squads:
		counts[_type_of(squad)] = counts.get(_type_of(squad), 0) + 1
	_tab_bar.add_child(_tab_button("Tất cả (%d)" % _squads.size(), ALL))
	for type in UnitData.TYPE_NAMES.size():
		if counts.has(type):
			_tab_bar.add_child(_tab_button("%s (%d)" % [UnitData.TYPE_NAMES[type], counts[type]], type))
	_tab_bar.add_child(_tab_button("Đã chọn (%d)" % _selected.size(), CHOSEN))
	if _tab >= 0 and not counts.has(_tab):
		_tab = ALL


func _tab_button(text: String, tab: int) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	button.set_pressed_no_signal(tab == _tab)
	button.pressed.connect(_show_tab.bind(tab))
	return button


func _fill_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var shown := _shown()
	if shown.is_empty():
		_grid.add_child(_label("Không còn đơn vị nào ở nhà." if _squads.is_empty() else "(trống)", 14, false))
		return
	for squad in shown:
		_grid.add_child(_tile(squad))


## A squad tile: the unit's icon, its name, soldiers / full and level mark; a gold frame and a
## check while chosen.
func _tile(squad: Army.Squad) -> Button:
	var unit: UnitData = _state.units[squad.unit_id]
	var chosen := _selected.has(squad)
	var level := squad.level()
	var tile := Button.new()
	tile.toggle_mode = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = TILE_SIZE
	tile.tooltip_text = "%s · %s — %d/%d lính" % [unit.display_name, Experience.SQUAD_LEVEL_NAMES[level],
			squad.soldiers, unit.squad_size]
	tile.set_pressed_no_signal(chosen)
	tile.pressed.connect(_toggle.bind(squad))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 4
	column.offset_right = -4
	column.offset_top = 3
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := ArmyDetailWindow.unit_icon(unit, TILE_ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	var name_label := _on_wood(unit.display_name, 11, UiPalette.ON_WOOD)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.custom_minimum_size.y = 28
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var count := _on_wood("%d/%d %s" % [squad.soldiers, unit.squad_size,
			Experience.SQUAD_LEVEL_MARKS[level] if level > 0 else ""], 11,
			UiPalette.WARNING_ON_WOOD if squad.soldiers < unit.squad_size else UiPalette.ON_WOOD_MUTED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(count)
	tile.add_child(column)
	if chosen:
		var frame := Panel.new()
		var border := StyleBoxFlat.new()
		border.draw_center = false
		border.set_border_width_all(3)
		border.border_color = UiPalette.GOLD
		frame.add_theme_stylebox_override("panel", border)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(frame)
		var check := _on_wood("✓", 16, UiPalette.GOLD)
		check.position = Vector2(6, 2)
		tile.add_child(check)
	return tile


## A label for a wooden button: not wrapped, ignores the mouse.
func _on_wood(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, false)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _header(text: String) -> Label:
	var label := _label(text, 15, false)
	label.add_theme_color_override("font_color", UiPalette.HEADER)
	return label


func _confirm() -> void:
	var result: Realm.Result
	if _force == null:
		result = _state.realm.form(_state, _general, _chosen())
	else:
		result = _state.realm.regroup(_state, _force, _chosen())
	if result != Realm.Result.OK:
		set_status(Realm.describe(result), false)
		return
	Sfx.play(&"recruit")
	done.emit()
	close()
