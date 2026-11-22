class_name RealmScreen
extends Control
## Full-screen realm map (Phân Chia Thiên Hạ, GDD §33, M18f-a), like the world map: the map on the
## left (70%), the selected town and army on the right (30%). Clicking a town selects it; with an
## army selected, clicking a neighboring kingdom town marches there and an enemy town asks to
## besiege it (`siege_requested`: the kingdom scene closes this screen and plays the battle).

signal closed
signal siege_requested(force: Realm.Force, town: int)

var _state: KingdomState
var _map: RealmMapView
var _panel: VBoxContainer
var _title: Label
var _town := Realm.HOME_CAPITAL
var _force: Realm.Force
## An enemy town the selected army may besiege, waiting for "Công thành!".
var _siege_target := -1
var _status_text := ""
var _status_good := true


func open(state: KingdomState) -> void:
	_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = UiPalette.BACKDROP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var top := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.theme_type_variation = &"WoodLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var back := Button.new()
	back.text = Touch.keys("Quay lại (Esc)")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(close)
	top.add_child(back)
	layout.add_child(_margin(top))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(row)
	_map = RealmMapView.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_stretch_ratio = 7.0
	_map.realm = state.realm
	_map.player_color = state.player_color
	_map.kingdom_name = state.kingdom_name
	_map.town_clicked.connect(_on_town_clicked)
	row.add_child(_map)
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_stretch_ratio = 3.0
	row.add_child(paper)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	var panel_margin := _margin(_panel)
	panel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_margin)
	_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()


## Opens with this town (and its first army) selected; for tests and previews.
func select_town(town: int) -> void:
	_town = town
	var here := _state.realm.forces_at(town)
	_force = here[0] if not here.is_empty() else null
	_siege_target = -1
	_refresh()


func _on_town_clicked(town: int) -> void:
	_status_text = ""
	# A neighbor of the selected army: show it with a march / siege button (never moves on a click).
	if _force != null and _state.realm.forces.has(_force) and RealmMap.are_neighbors(_force.town, town):
		_town = town
		_siege_target = town
		_refresh()
		return
	_town = town
	_siege_target = -1
	var here := _state.realm.forces_at(town)
	_force = here[0] if not here.is_empty() else null
	_refresh()


func _set_status(text: String, good: bool) -> void:
	_status_text = text
	_status_good = good
	if not good:
		Sfx.play(&"error")


func _refresh() -> void:
	var realm := _state.realm
	if _force != null and not realm.forces.has(_force):
		_force = null
	_title.text = "Thiên hạ — Phân Chia Thiên Hạ (lượt %d)" % _state.turn
	_map.selected_town = _town
	_map.selected_force = _force
	_map.queue_redraw()
	for child in _panel.get_children():
		child.queue_free()
	_panel.add_child(_line("Trấn của ta: %d/%d · Đạo quân: %d · Tướng: %d/%d" % [realm.count_owned(Realm.PLAYER),
			RealmMap.TOWN_COUNT, realm.forces.size(), _state.generals.generals.size(), _state.generals.max_generals], 14,
			UiPalette.MUTED))
	_panel.add_child(HSeparator.new())
	_fill_town(realm.towns[_town])
	if _force != null:
		_panel.add_child(HSeparator.new())
		_fill_force(_force)
	if _status_text != "":
		_panel.add_child(_line(_status_text, 14, UiPalette.GOOD if _status_good else UiPalette.WARNING))


func _fill_town(town: Realm.Town) -> void:
	var realm := _state.realm
	var owner_color := realm.owner_color(town, _state.player_color)
	_panel.add_child(_line(("♛ " if town.is_capital() else "") + town.name, 20, UiPalette.ink(owner_color)))
	var kind := "Kinh đô" if town.is_capital() else "Trấn"
	_panel.add_child(_line("%s của %s" % [kind, realm.owner_name(town, _state.kingdom_name)], 15))
	if town.owner != Realm.PLAYER:
		var nation := realm.nations[town.owner]
		_panel.add_child(_line("Quân thủ: %d/%d lính · %s" % [town.garrison, town.max_garrison,
				RealmMap.nation_data(nation.id).trait], 14))
		_panel.add_child(_line("Tường thành: phòng thủ +%d%%, sĩ khí +%d" % [
				roundi((Realm.CAPITAL_WALL_DEFENSE if town.is_capital() else Realm.WALL_DEFENSE) * 100),
				roundi(Realm.CAPITAL_WALL_MORALE if town.is_capital() else Realm.WALL_MORALE)], 14, UiPalette.MUTED))
		if town.is_capital():
			_panel.add_child(_line("Chiếm kinh đô thì %s bị diệt, mọi trấn còn lại về tay ta." % nation.name, 14,
					UiPalette.MUTED))
	elif town.is_captured():
		var view := RequirementView.new()
		_panel.add_child(view)
		view.amounts("Mỗi lượt", realm.town_yield(town), false)
		_panel.add_child(_line("+%d đơn vị tối đa · bổ sung quân +%d%%" % [
				Realm.TOWN_SQUADS,
				roundi(Realm.TOWN_REPLENISH * 100)], 14))
		_panel.add_child(_line("Dân binh giữ trấn: %d lính" % realm.militia_soldiers(town), 14))
		if town.governor != null:
			_panel.add_child(_line("Thái thú: %s %s" % [town.governor.name, town.governor.star_text()], 15,
					town.governor.name_color()))
			_panel.add_child(_button("Triệu hồi thái thú", func() -> void:
				realm.remove_governor(_state, town.id)
				_refresh()))
		else:
			_panel.add_child(_line("Chưa có thái thú: trấn chỉ nộp nửa sản lượng.", 14, UiPalette.WARNING))
			_panel.add_child(_button("Bổ nhiệm thái thú", _open_governor.bind(town)))
		if not realm.nations[town.nation].destroyed:
			_panel.add_child(_line("%s có thể đánh chiếm lại trấn này." % realm.nations[town.nation].name, 13,
					UiPalette.MUTED))
	else:
		_panel.add_child(_line("Đất của các gia tộc đã thống nhất. Đạo quân đứng ở trấn của ta được bổ sung lính mỗi lượt nếu không hành quân%s." % (
				" (kinh đô bổ sung nhanh gấp đôi)" if town.id == Realm.HOME_CAPITAL else ""), 14))
		_panel.add_child(_line("+%d đơn vị tối đa" % Realm.TOWN_SQUADS, 14))
	if town.id == Realm.HOME_CAPITAL:
		_panel.add_child(_button("Lập đạo quân mới", _open_army.bind(null)))
	var here := realm.forces_at(town.id)
	if not here.is_empty():
		_panel.add_child(_line("Đạo quân tại đây:", 15))
		for force in here:
			var button := _button("%s%s — %d đơn vị, %d lính" % ["▶ " if force == _force else "", force.general.name,
					force.squads.size(), force.soldiers()], _select_force.bind(force))
			_panel.add_child(button)
	if _siege_target == town.id and _force != null:
		_fill_siege(town)


func _fill_force(force: Realm.Force) -> void:
	var general := force.general
	_panel.add_child(_line("Đạo quân %s" % general.name, 18, UiPalette.ink(_state.player_color)))
	_panel.add_child(_line("Tướng %s %s · Võ lực %d · Thống suất %d%s" % [general.name, general.star_text(),
			general.total_might(), general.total_command(),
			" · bị thương, còn %d lượt" % general.wounded_turns if general.wounded_turns > 0 else ""], 14))
	_panel.add_child(_line("%d/%d đơn vị · %d lính" % [force.squads.size(), Realm.MAX_ARMY_SQUADS, force.soldiers()], 14))
	var counts := {}
	for squad in force.squads:
		counts[squad.unit_id] = counts.get(squad.unit_id, 0) + 1
	var parts: Array[String] = []
	for unit_id in counts:
		parts.append("%s ×%d" % [_state.units[unit_id].display_name, counts[unit_id]])
	_panel.add_child(_line(", ".join(parts), 13, UiPalette.MUTED))
	if force.moved:
		_panel.add_child(_line("Đã hành quân lượt này.", 14, UiPalette.MUTED))
	else:
		_panel.add_child(_line("Bấm một trấn kề rồi chọn: vòng xanh để hành quân, vòng đỏ để công thành.", 14))
	if force.town == Realm.HOME_CAPITAL:
		_panel.add_child(_button("Điều chỉnh quân", _open_army.bind(force)))
		var disband := _button("Giải tán đạo quân", func() -> void: pass)
		disband.pressed.connect(func() -> void:
			if disband.has_meta("armed"):
				_state.realm.disband(_state, force)
				_force = null
				_refresh()
			else:
				disband.set_meta("armed", true)
				disband.text = "Bấm lần nữa để giải tán")
		_panel.add_child(disband)


func _fill_siege(town: Realm.Town) -> void:
	_panel.add_child(HSeparator.new())
	var force := _force
	if town.owner == Realm.PLAYER:
		var move := _state.realm.check_move(force, town.id)
		if move != Realm.Result.OK:
			_panel.add_child(_line(Realm.describe(move), 14, UiPalette.WARNING))
			return
		_panel.add_child(_button("Hành quân tới %s" % town.name, func() -> void:
			_state.realm.move(force, town.id)
			Sfx.play(&"place_land")
			_siege_target = -1
			_refresh()))
		return
	var check := _state.realm.check_siege(_force, town.id)
	_panel.add_child(_line("Công thành %s bằng đạo quân %s?" % [town.name, _force.general.name], 16, UiPalette.WARNING))
	_panel.add_child(_line("Ta %d lính · Quân thủ %d lính sau tường thành." % [_force.soldiers(), town.garrison], 14))
	if check != Realm.Result.OK:
		_panel.add_child(_line(Realm.describe(check), 14, UiPalette.WARNING))
		return
	_panel.add_child(_button("Công thành!", func() -> void:
		siege_requested.emit(force, town.id)))


func _select_force(force: Realm.Force) -> void:
	_force = force
	_siege_target = -1
	_refresh()


func _open_army(force: Realm.Force) -> void:
	var dialog := ArmyDialog.new()
	add_child(dialog)
	dialog.open(_state, force)
	dialog.done.connect(func() -> void:
		if force == null and not _state.realm.forces.is_empty():
			_force = _state.realm.forces.back()
		_refresh())


func _open_governor(town: Realm.Town) -> void:
	var dialog := GovernorDialog.new()
	add_child(dialog)
	dialog.open(_state, town)
	dialog.done.connect(_refresh)


func _line(text: String, font_size: int, color: Color = UiPalette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(on_pressed)
	return button


func _margin(child: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	margin.add_child(child)
	return margin
