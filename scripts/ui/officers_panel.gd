class_name OfficersPanel
extends VBoxContainer
## The "Tướng sĩ" side tab (GDD §13, M12c, Ninja Village style): one row per general and advisor
## with their battle sprite, name, stars, post, level and status, then the limit-break scrolls held
## (M16c). Tapping a row emits
## `officer_selected`; the kingdom scene opens the officer's window. Read-only.

signal officer_selected(officer: Officer)
## "Đặc vụ" under the lists: the kingdom scene opens the Sở cảnh sát's agents tab (GDD §8 M14e).
signal agents_requested

const ROW_HEIGHT := 76
const WARNING_COLOR := UiPalette.WARNING


func refresh(state: KingdomState) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var generals := state.generals
	add_child(_header("Tướng (%d/%d)" % [generals.generals.size(), Generals.MAX_GENERALS]))
	if generals.generals.is_empty():
		add_child(_small("Chưa có tướng nào. Tuyển ở thành chính, tab Chiêu hiền."))
	for general in generals.generals:
		var role := "Tổng tướng" if general == generals.commander else "Dự bị"
		add_child(_row(state, general, role))
	var advisors := state.advisors
	add_child(_header("Mưu sĩ (%d/%d)" % [advisors.advisors.size(), Advisors.MAX_ADVISORS]))
	if advisors.advisors.is_empty():
		add_child(_small("Chưa có mưu sĩ nào. Tuyển ở thành chính, tab Chiêu hiền."))
	for advisor in advisors.advisors:
		var role := Advisors.POST_NAMES[advisor.post] if advisor.post != Advisor.NO_POST else "Chưa giữ chức"
		add_child(_row(state, advisor, role))
	add_child(_small("Bí kíp đột phá: %d (có được khi dẹp yên một vùng nổi loạn)." % state.scrolls))
	var agents := state.agents.agents
	var busy := agents.filter(func(a: Agent) -> bool: return a.is_busy()).size()
	add_child(_header("Đặc vụ (%d/%d)" % [agents.size(), state.agent_slots()]))
	var button := Button.new()
	button.text = "Đặc vụ" + (" · %d đang làm nhiệm vụ" % busy if busy > 0 else "")
	button.custom_minimum_size = Vector2(0, 40)
	button.disabled = state.police_level() == 0
	button.pressed.connect(func() -> void: agents_requested.emit())
	add_child(button)
	if button.disabled:
		add_child(_small("Cần Sở cảnh sát (thành cấp 3) để tuyển và cử đặc vụ."))


## A tappable row: battle sprite, "Name ★★", "role · level", wounds, unspent points and whether a
## limit break is possible.
func _row(state: KingdomState, officer: Officer, role: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent) -> void:
		# On release over the row, like a button: a drag that scrolls the list ends elsewhere (DragScroll).
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and Rect2(Vector2.ZERO, panel.size).has_point(event.position):
			officer_selected.emit(officer))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var figure := OfficerFigure.new()
	figure.setup(officer, 2)
	row.add_child(figure)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	column.add_child(_line("%s %s" % [officer.name, officer.star_text()], 14, officer.name_color()))
	var breaks := " · Đột phá %d" % officer.breaks if officer.breaks > 0 else ""
	column.add_child(_line("%s · Cấp %d%s" % [role, officer.level, breaks], 12, UiPalette.MUTED))
	if officer.away:
		column.add_child(_line("Đang đi thảo phạt", 12, UiPalette.ACCENT))
	elif not officer.is_ready():
		column.add_child(_line("Bị thương, còn %d lượt" % officer.wounded_turns, 12, WARNING_COLOR))
	if officer.points > 0:
		column.add_child(_line("Còn %d điểm cộng" % officer.points, 12, UiPalette.ACCENT))
	if state.check_limit_break(officer) == LimitBreak.Result.OK:
		column.add_child(_line("Có thể đột phá", 12, UiPalette.ACCENT))
	return panel


func _header(text: String) -> Label:
	var label := _line(text, 15, UiPalette.HEADER)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _small(text: String) -> Label:
	var label := _line(text, 12, UiPalette.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _line(text: String, font_size: int, color: Color = UiPalette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
