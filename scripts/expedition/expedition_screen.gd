class_name ExpeditionScreen
extends Control
## The full-screen replay of one expedition stage (ExpeditionView) with speed buttons and a skip,
## then the stage's statistics (GDD §15 M14i). Its own music. `closed` when the player is done.

signal closed

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const STATS_COLUMNS: Array[String] = ["Đơn vị", "Lính", "Mất", "Hạ", "Kết cục"]

var _view: ExpeditionView
var _report: Dictionary
var _speed_buttons: Array[Button] = []
var _skip_button: Button
var _stats_shown := false


## `report`: the stage (Expedition.run_stage, plus "rewards" when it was the last one).
func open(report: Dictionary, stages: int) -> void:
	_report = report
	theme = BattleScreen._dark_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BattleScreen.BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var stage_text := "Ải %d/%d" % [report.stage + 1, stages]
	var title := Label.new()
	title.text = "Thảo phạt quân nổi loạn — %s" % stage_text
	title.add_theme_font_size_override("font_size", 20)
	layout.add_child(_margin(title, 8))
	_view = ExpeditionView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var battles: Array[BattleRecord] = []
	battles.assign(report.battles)
	_view.setup(battles, stage_text)
	_view.finished.connect(_show_stats)
	layout.add_child(_view)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in SPEEDS.size():
		var button := _button("x%d" % SPEEDS[i], _select_speed.bind(i))
		button.toggle_mode = true
		_speed_buttons.append(button)
		row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_skip_button = _button("Bỏ qua tới kết quả", func() -> void: _view.skip())
	row.add_child(_skip_button)
	layout.add_child(_margin(row, 8))
	_select_speed(0)
	Sfx.music(&"expedition")


func _select_speed(index: int) -> void:
	_view.set_speed(SPEEDS[index])
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == index)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		if _stats_shown:
			_close()
		else:
			_view.skip()
	get_viewport().set_input_as_handled()


## The stage's statistics on paper over the replay: battles, the team's units, rewards.
func _show_stats() -> void:
	if _stats_shown:
		return
	_stats_shown = true
	_skip_button.disabled = true
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.theme = null
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(_margin(column, 20))
	var won: bool = _report.won
	var title := _paper_label("Ải %d: %s" % [_report.stage + 1, "vượt ải!" if won else "thất bại"], 22)
	title.add_theme_color_override("font_color", UiPalette.GOOD if won else UiPalette.WARNING)
	column.add_child(title)
	for line in summary_lines(_report):
		column.add_child(_paper_label(line, 15))
	var grid := GridContainer.new()
	grid.columns = STATS_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 18)
	for heading in STATS_COLUMNS:
		grid.add_child(_paper_label(heading, 14, UiPalette.MUTED))
	for row in unit_rows(_report):
		for key in ["name", "start", "lost", "kills", "fate"]:
			grid.add_child(_paper_label(str(row[key]), 14))
	column.add_child(grid)
	var close := _button("Đóng (Enter)", _close)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(close)
	ScreenFit.shrink_to_fit(panel, get_viewport_rect().size)


func _close() -> void:
	Sfx.music(&"kingdom")
	closed.emit()
	queue_free()


## The stage's result in a few lines: battles, the rebel general, fates, and the rewards when the
## expedition is over.
static func summary_lines(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var battles: Array = report.battles
	var won := 0
	for record: BattleRecord in battles:
		won += 1 if record.winner == BattleRecord.ATTACKER else 0
	lines.append("Trận đã đánh: %d · thắng %d." % [battles.size(), won])
	if report.get("boss", "") != "":
		lines.append("Tướng nổi loạn %s xuất hiện cuối ải%s." % [report.boss, " và đã bị đánh bại" if report.won else ""])
	match report.get("general_fate", &"none"):
		&"dead":
			lines.append("Tướng dẫn đội đã tử trận!")
		&"wounded":
			lines.append("Tướng dẫn đội bị thương, nghỉ %d lượt." % Generals.WOUND_TURNS)
	if report.get("advisor_fate", &"none") == &"wounded":
		lines.append("Mưu sĩ bị thương, nghỉ %d lượt." % Advisors.WOUND_TURNS)
	if report.won and not report.get("finished", false):
		lines.append("Cả đội đã hồi phục; lượt sau tiến vào ải tiếp theo.")
	var rewards: Dictionary = report.get("rewards", {})
	if not rewards.is_empty():
		lines.append("Đội thảo phạt trở về%s." % (": vùng nổi loạn đã được dẹp yên" if report.get("cleared", false) else ""))
		if report.has("relation"):
			lines.append("Các gia tộc cảm kích: quan hệ +%d với mọi gia tộc." % report.relation)
		var amounts: Dictionary[StringName, int] = {}
		amounts.assign(rewards.resources)
		var text := UiFormat.amounts(amounts, ResourceTypeData.load_all())
		if not text.is_empty():
			lines.append("Thu được: %s." % text)
		var items: Array = rewards.items
		if not items.is_empty():
			lines.append("Trang bị: %s." % ", ".join(items.map(func(item: Item) -> String:
				return "%s (%s)" % [item.display_name, Item.RARITY_NAMES[item.rarity]])))
		if rewards.xp_officer > 0:
			lines.append("Kinh nghiệm: tướng sĩ +%d, lính +%d." % [rewards.xp_officer, rewards.xp_squad])
	return lines


## One row per unit of the team over the stage's battles: {"name", "start", "lost", "kills", "fate"}.
static func unit_rows(report: Dictionary) -> Array[Dictionary]:
	var rows := {}
	var order: Array = []
	var battles: Array = report.battles
	for b in battles.size():
		var record: BattleRecord = battles[b]
		var side := record.sides[BattleRecord.ATTACKER]
		for unit in side.units:
			var key: Variant = unit.squad if unit.squad != null else "guard"
			if not rows.has(key):
				order.append(key)
				rows[key] = {"name": "Cận vệ của %s" % side.general_name if unit.is_general_guard else unit.data.display_name,
						"start": unit.start_soldiers, "lost": 0, "kills": 0, "fate": "Còn"}
			var row: Dictionary = rows[key]
			row.lost += unit.lost()
			row.kills += roundi(unit.kills)
			if unit.alive() == 0:
				row.fate = "Tử trận"
			elif unit.broken or record.winner != BattleRecord.ATTACKER:
				row.fate = "Bỏ chạy"
	var result: Array[Dictionary] = []
	for key in order:
		result.append(rows[key])
	return result


func _paper_label(text: String, font_size: int, color: Color = UiPalette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _margin(child: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, amount)
	margin.add_child(child)
	return margin


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120, 40)
	button.pressed.connect(on_pressed)
	return button
