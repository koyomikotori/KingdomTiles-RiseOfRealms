class_name ExpeditionWindow
extends ModalWindow
## Tapping the uprising zone (GDD §15 M14i). With no expedition out: "Quân địch" (the zone, its
## stages and ambushes, the rebel general's chance, the rewards) and "Cử quân" (one general, one
## advisor, up to Expedition.MAX_SQUADS squads; "Tiến hành thảo phạt" sends them and closes the
## window). With one on the way: its progress, and the replays of the stages fought so far.

## "Xem lại ải N": the kingdom scene opens the replay of that stage (`index` = N - 1).
signal replay_requested(index: int)

const LIST_HEIGHT := 360
const RESERVED := 300

var _state: KingdomState
var _general: General
var _advisor: Advisor
var _chosen: Array[Army.Squad] = []
var _accept_duels := true
var _pick_box: VBoxContainer
var _count_label: Label
var _send_button: Button


## `replays`: how many stages (from the first) can be watched again, 0 when none.
func open(state: KingdomState, replays: int = 0) -> void:
	_state = state
	var uprising := state.uprising
	if state.expedition != null:
		var expedition := state.expedition
		var body := build_frame("Thảo phạt: đã qua %d/%d ải" % [expedition.stage, expedition.stages],
				UiPalette.WARNING, 0.46)
		body.add_child(_label(_team_text(expedition), 15))
		body.add_child(HSeparator.new())
		if expedition.log.is_empty():
			body.add_child(_muted("Đội đang hành quân: ải đầu tiên đánh vào cuối lượt này."))
		for line in expedition.log:
			body.add_child(_label("• " + line, 15))
		body.add_child(_muted("Mỗi lượt đánh một ải vào cuối lượt; trận được phát lại ở đầu lượt sau."))
		for index in replays:
			add_action("Xem lại ải %d" % (index + 1), func() -> void:
				replay_requested.emit(index)
				close())
		return
	var body := build_frame("Vùng nổi loạn (%d ô)" % uprising.cells.size(), UiPalette.WARNING, 0.56)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, fit_height(LIST_HEIGHT, RESERVED))
	body.add_child(tabs)
	_fill_enemy_tab(_tab(tabs, "Quân địch"))
	_pick_box = _tab(tabs, "Cử quân")
	_send_button = add_action("Tiến hành thảo phạt", _send)
	_refresh_pick()


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _fill_enemy_tab(box: VBoxContainer) -> void:
	var uprising := _state.uprising
	var stages := Expedition.stages_for(_state.castle_level)
	var ambushes := Expedition.ambushes_for(_state.castle_level)
	box.add_child(_label(("Đạo tặc và quân nổi loạn chiếm %d ô đất: công trình ở đó ngừng hoạt động, không đặt đất hay xây "
			+ "được. Không dẹp thì cứ %d lượt vùng này lan thêm một ô.") % [uprising.cells.size(), Uprising.GROW_TURNS], 15))
	box.add_child(_label("Thành cấp %d: %d ải, mỗi ải %d trận phục kích liền nhau, mỗi lượt đi một ải." % [
			_state.castle_level, stages, ambushes], 15))
	for stage in stages:
		var units := Expedition.enemy_units_for(stage, uprising.cleared, uprising.size_factor())
		var level := Expedition.enemy_level_for(stage, uprising.cleared)
		box.add_child(_label("• Ải %d: mỗi trận khoảng %d–%d đơn vị cướp (%s), %d%% gặp tướng nổi loạn cuối ải." % [
				stage + 1, maxi(1, units - 1), mini(Expedition.MAX_ENEMY_UNITS, units + 1), Experience.SQUAD_LEVEL_NAMES[level],
				roundi(Expedition.boss_chance(stage, uprising.cleared) * 100)], 14))
	box.add_child(HSeparator.new())
	box.add_child(_muted(("Đánh liên tục: đơn vị bỏ chạy hoặc bị tiêu diệt là mất luôn; hết mỗi ải cả đội hồi phục. Thua một "
			+ "trận là cả đội tan: tướng ngã ngựa có thể tử trận, mưu sĩ có thể bị thương.")))
	var per_stage := roundi(Expedition.STAGE_RESOURCES * uprising.size_factor())
	box.add_child(_label(("Phần thưởng khi về: mỗi trận thắng tướng sĩ +%d, lính +%d kinh nghiệm; mỗi ải vượt qua %d × số thứ "
			+ "tự ải mỗi loại lương thực / gỗ / đá và một món trang bị (ải sau dễ ra đồ hiếm). Vùng càng to thưởng càng nhiều.") % [
			Expedition.WIN_OFFICER_XP, Expedition.WIN_SQUAD_XP, per_stage], 14))


## The general, advisor and squad choices.
func _refresh_pick() -> void:
	for child in _pick_box.get_children():
		_pick_box.remove_child(child)
		child.queue_free()
	_pick_box.add_child(_label("Tướng dẫn đội:", 15, false))
	var generals := HFlowContainer.new()
	_pick_box.add_child(generals)
	generals.add_child(_choice("Không cử", _general == null, func() -> void:
		_general = null
		_refresh_pick()))
	for general in _state.generals.generals:
		var button := _choice("%s %s" % [general.name, general.star_text()], _general == general, func() -> void:
			_general = general
			_refresh_pick())
		button.disabled = not general.is_ready()
		generals.add_child(button)
	_pick_box.add_child(_label("Mưu sĩ:", 15, false))
	var advisors := HFlowContainer.new()
	_pick_box.add_child(advisors)
	advisors.add_child(_choice("Không cử", _advisor == null, func() -> void:
		_advisor = null
		_refresh_pick()))
	for advisor in _state.advisors.advisors:
		var post := " · " + Advisors.POST_NAMES[advisor.post] if advisor.post != Advisor.NO_POST else ""
		var button := _choice("%s %s%s" % [advisor.name, advisor.star_text(), post], _advisor == advisor, func() -> void:
			_advisor = advisor
			_refresh_pick())
		button.disabled = not advisor.is_ready()
		advisors.add_child(button)
	if _advisor != null and _advisor.post != Advisor.NO_POST:
		_pick_box.add_child(_muted("Mưu sĩ giữ chức %s: chức này tạm mất tác dụng tới khi họ về." % Advisors.POST_NAMES[_advisor.post]))
	if _general != null and _general == _state.generals.commander:
		_pick_box.add_child(_muted("Tổng tướng đi vắng: quân ở nhà đánh không có tướng cho tới khi về."))
	if _general != null:
		var duel := _check_box("Nhận lời thách đấu của tướng nổi loạn", _accept_duels)
		duel.toggled.connect(func(on: bool) -> void: _accept_duels = on)
		_pick_box.add_child(duel)
		_pick_box.add_child(_muted(("Mỗi ải có %d%% tướng nổi loạn ra thách đấu tay đôi, người thua tử trận. Thắng: ải sau quân "
				+ "nổi loạn %+d nhuệ khí tối đa; thua: ải sau quân ta %+d. Không nhận: quân ta %+d trong ải đó.") % [
				roundi(Expedition.DUEL_CHANCE * 100), -Expedition.DUEL_MORALE, -Expedition.DUEL_MORALE,
				Expedition.DECLINE_MORALE]))
	_count_label = _label("", 15, false)
	_pick_box.add_child(_count_label)
	var squads := GridContainer.new()
	squads.columns = 2
	_pick_box.add_child(squads)
	for squad in _state.army.squads:
		var unit := _state.units[squad.unit_id]
		var box := _check_box("%s (%d/%d lính)" % [unit.display_name, squad.soldiers, unit.squad_size], _chosen.has(squad))
		box.disabled = squad.away or (not _chosen.has(squad) and _chosen.size() >= Expedition.MAX_SQUADS)
		box.toggled.connect(func(on: bool) -> void:
			if on:
				_chosen.append(squad)
			else:
				_chosen.erase(squad)
			_refresh_pick())
		squads.add_child(box)
	_count_label.text = "Lính (%d/%d đơn vị):" % [_chosen.size(), Expedition.MAX_SQUADS]
	_pick_box.add_child(_muted("Lính đi vắng vẫn tốn phí nuôi, không đánh trận ở nhà và không tự bổ sung quân."))
	var result := _state.check_expedition(_general, _advisor, _chosen)
	_send_button.disabled = result != KingdomState.ExpeditionResult.OK
	set_status("" if result == KingdomState.ExpeditionResult.OK else KingdomState.describe_expedition(result), true)


func _check_box(text: String, pressed: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	box.focus_mode = Control.FOCUS_NONE
	for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		box.add_theme_color_override(color_name, UiPalette.ON_WOOD)
	box.add_theme_color_override("font_disabled_color", Color(UiPalette.ON_WOOD, 0.45))
	return box


func _send() -> void:
	var result := _state.start_expedition(_general, _advisor, _chosen, _accept_duels)
	if result != KingdomState.ExpeditionResult.OK:
		set_status(KingdomState.describe_expedition(result), false)
		return
	Sfx.play(&"recruit")
	close()


func _team_text(expedition: Expedition) -> String:
	var parts: Array[String] = []
	if expedition.general != null:
		parts.append("Tướng %s" % expedition.general.name)
	if expedition.advisor != null:
		parts.append("Mưu sĩ %s" % expedition.advisor.name)
	parts.append("%d đơn vị lính" % expedition.squads.size())
	if expedition.general != null:
		parts.append("%s thách đấu" % ("nhận" if expedition.accept_duels else "không nhận"))
	return "Đội thảo phạt: %s. Đã thắng %d trận." % [", ".join(parts), expedition.wins]


func _choice(text: String, chosen: bool, on_pressed: Callable) -> Button:
	var button := _button(text, on_pressed)
	button.toggle_mode = true
	button.button_pressed = chosen
	button.custom_minimum_size = Vector2(140, 38)
	return button


func _muted(text: String) -> Label:
	var label := _label(text, 13)
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label
